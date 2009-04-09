#!/usr/bin/ruby1.8 -w
#
# Copyright:: Copyright 2009 Google Inc.
# Original Author:: Ryan Brown (mailto:ribrdb@google.com)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Datamapper adapter for Google App Engine

require 'appengine-apis/datastore'

module DataMapper
  module Adapters
    class AppEngineAdapter < AbstractAdapter
      Datastore = AppEngine::Datastore

      def initialize(name, uri_or_options)
        super
        if uri_or_options.kind_of? Hash
          options = uri_or_options
          if options['host'] == 'memory'
            require 'appengine-apis/testing'
            begin
              AppEngine::ApiProxy.get_app_id
            rescue NoMethodError
              AppEngine::Testing::install_test_env
            end
            AppEngine::Testing::install_test_datastore
          end
        end
        @resource_naming_convention = lambda do |value|
          Extlib::Inflection.pluralize(Extlib::Inflection.camelize(value))
        end
      end

      def kind(model)
        model.storage_name(name)
      end

      def create(resources)
        created = 0
        entities = []
        resources.each do |resource|
          repository = resource.repository
          model = resource.model
          attributes = resource.attributes
          
          
          kind = self.kind(model)
          keys = model.key(repository.name)
          raise "Multiple keys in #{resource.inspect}" if keys.size > 1
          if keys.size == 1
            key = attributes.delete(keys[0].name)
            key = key.to_s if key
          end
          if key && !(key == 0 || keys[0].serial?)
            entity = Datastore::Entity.new(kind, key)
          else
            entity = Datastore::Entity.new(kind)
          end
          
          attributes.each do |name, value|
            entity.set_property(name.to_s, value)
          end
          entities << entity
          created += 1
        end
        Datastore.put(entities)
        resources.zip(entities) do |resource, entity|
          key = entity.key
          if identity_field = resource.model.identity_field(name)
            identity_field.set!(resource, key.get_name || key.get_id)
          end
          resource.instance_variable_set :@__entity__, entity
        end
        return created
      end

      def read(query)
        query = QueryBuilder.new(query, kind(query.model), self)
        query.run
      end

      def update(attributes, collection)
        attributes = attributes_as_fields(attributes)
        entities = collection.collect do |resource|
          entity = resource.instance_variable_get :@__entity__
          entity.update(attributes)
        end

        Datastore.put(entities)
        entities.size
      end

      def delete(collection)
        keys = collection.collect do |resource|
          entity = resource.instance_variable_get :@__entity__
          entity.key
        end
        Datastore.delete(keys)
      end
    
      class QueryBuilder
        import Datastore::JavaDatastore::FetchOptions
        include Datastore::Query::Constants
        @@OPERATORS = {
          Conditions::EqualToComparison => EQUAL,
          Conditions::GreaterThanComparison => GREATER_THAN,
          Conditions::GreaterThanOrEqualToComparison => GREATER_THAN_OR_EQUAL,
          Conditions::LessThanComparison => LESS_THAN,
          Conditions::LessThanOrEqualToComparison => LESS_THAN_OR_EQUAL,
          }.freeze
      
        def initialize(query, kind, adapter)
          @model = query.model
          @kind = kind
          @limit = query.limit
          @offset = query.offset
          @maybe_get = true
          @must_be_get = false
          @keys = []
          @dm_query = query
          @adapter_name = adapter.name
        
          @query = Datastore::Query.new(kind)
          parse_order(query.order)
          parse_conditions(query.conditions)
          raise NotImplementedError if @must_be_get && !@maybe_get
        end
      
        def property_name(property, qualify=false)
          if qualify
            table_name = property.model.storage_name(name)
            "#{table_name}.#{property.field}"
          else
            property.field
          end
        end
      
        def parse_order(order)
          if order.size == 1 && order[0].direction != :desc
            if order[0].property.key?
              # omit the default key ordering.
              # This lets inequality filters work
              return
            end
          end
          order.map do |order|
            if order.direction == :desc
              direction = DESCENDING
            else
              direction = ASCENDING
            end
            name = if order.property.key?
              '__key__'
            else
              property_name(order.property)
            end
            @query.add_sort(name, direction)
          end
        end
      
        def parse_conditions(conditions)
          case conditions
          when Conditions::NotOperation then
            raise NotImplementedError, "NOT operator is not supported"
          when Conditions::AbstractComparison then
            parse_comparison(conditions)
          when Conditions::OrOperation  then
            parse_or(conditions)
          when Conditions::AndOperation then
            parse_and(conditions)
          else
            raise ArgumentError, "invalid conditions #{conditions.class}: #{conditions.inspect}"
          end
        end

        def parse_key(property, value)
          unless property.key?
            raise ArgumentError, "#{property_name(property, true)} is not the key"
          end
          case value
          when Integer, String
            Datastore::Key.from_path(@kind, value)
          when Symbol
            Datastore::Key.from_path(@kind, value.to_s)
          else
            raise ArgumentError "Unsupported key value #{value.inspect} (a #{value.class})"
          end
        end
      
        def parse_or(or_op)
          if !@maybe_get
            raise NotImplementedError, "OR only supported with key equality comparisons"
          end
          @must_be_get = true
          or_op.operands.each do |op|
            case op
              when Conditions::OrOperation  then
                parse_or(op)
              when Conditions::EqualToComparison then
                key = parse_key(op.property, op.value)
                @keys << key
              when Conditions::InclusionComparison then
                parse_key_inclusion(op)
              else
                raise NotImplementedError, "Unsupported condition #{op.class} inside OR"
            end
          end
        end
      
        def parse_key_inclusion(op)
          raise NotImplementedError unless op.value.kind_of? Array
          op.value.each do |value|
            @keys << parse_key(op.property, value)
          end
        end
      
        def parse_and(op)
          if @maybe_get && (@found_and || op.operands.size > 1)
            @maybe_get = false
          end
          @found_and = true
          op.operands.each do |conditions|
            parse_conditions(conditions)
          end
        end
      
        def parse_comparison(op)
          property = op.property
          value = op.value
          if @maybe_get
            if property.key?
              case op
              when Conditions::EqualToComparison 
                @keys << parse_key(property, value)
              when Conditions::InclusionComparison
                parse_key_inclusion(op)
                @must_be_get = true
                return
              else
                @maybe_get = false
              end
            else
              @maybe_get = false
            end
          end
        
          if op.kind_of? Conditions::InclusionComparison
            parse_range(op)
          else
            filter_op = @@OPERATORS[op.class]
            if filter_op.nil?
              raise ArgumentError, "#{op.class} is not a supported comparison"
            end
            @query.filter(property_name(op.property), filter_op, op.value)
          end
        end
      
        def parse_range(op)
          range = op.value
          raise NotImplementedError unless range.is_a? Range
          name = property_name(op.property)
          begin_op = GREATER_THAN_OR_EQUAL
          end_op = if range.exclude_end?
            LESS_THAN
          else
            LESS_THAN_OR_EQUAL
          end
          @query.filter(name, begin_op, range.begin)
          @query.filter(name, end_op, range.end)
        end
      
        def is_get?
          @maybe_get && @keys.size > 0
        end
      
        def get_entities
          if is_get?
            Datastore.get(@keys)
          else
            begin
              chunk_size = FetchOptions::DEFAULT_CHUNK_SIZE
              options = FetchOptions::Builder.with_chunk_size(
                  chunk_size)
              options.limit(@limit) if @limit
              options.offset(@offset) if @offset
              @query.iterator(options).collect {|e| e}
            rescue java.lang.IllegalArgumentException => ex
              raise ArgumentError, ex.message
            end
          end
        end
      
        def run
          key_prop = @model.key(@adapter_name)[0].field
          get_entities.map do |entity|
            entity_to_model(key_prop, entity)
          end
        end
      
        def entity_to_model(key_prop, entity)
          # TODO: This is broken. We should be setting all properties
          return if entity.nil?
          key = entity.get_key
          values = @dm_query.fields.map do |property|
            if property.key?
              key.get_name || key.get_id
            else
              entity.get_property(property.field)
            end
          end
          resource = @model.load(values, @dm_query)
          resource.instance_variable_set :@__entity__, entity
          resource
        end
      
        def keys
          @keys
        end
      end
    end
    
    const_added(:AppEngineAdapter)
  end
end
