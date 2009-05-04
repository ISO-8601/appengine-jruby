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

require File.dirname(__FILE__) + '/spec_helper'
require 'dm-core/spec/adapter_shared_spec'

class TextTest
  include DataMapper::Resource
  
  property :id, Serial
  property :text, Text
end

describe DataMapper::Adapters::AppEngineAdapter do
  before :all do
    AppEngine::Testing.install_test_env
    AppEngine::Testing.install_test_datastore
  end

  before :all do
    @adapter = DataMapper.setup(:default, "app_engine://memory")
    @repository = DataMapper.repository(@adapter.name)
    
    AppEngine::Testing.install_test_datastore
  end
  
  def pending_if(message, boolean = true)
    if boolean
      pending(message) { yield }
    else
      yield
    end
  end

  it_should_behave_like 'An Adapter'
  
  describe 'create' do
    it 'should support Text' do
      a = TextTest.new(:text => "a" * 1024)
      a.save
    end
  end
  
  describe 'update' do
    it 'should support Text' do
      a = TextTest.new(:text => "a" * 1024)
      a.save
      a.text = "A" * 1024
      a.save
      a.reload
      a.text.should be_a(AppEngine::Datastore::Text)
      a.text.should be_a(String)
    end
  end
end
