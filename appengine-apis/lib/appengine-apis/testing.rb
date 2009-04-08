#!/usr/bin/ruby1.8 -w
#
# Copyright:: Copyright 2007 Google Inc.
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
#
# Helpers for installing stub apis in unit tests.

require 'appengine-apis/apiproxy'

module AppEngine
  module Testing
    import com.google.appengine.tools.development.ApiProxyLocalFactory
    import com.google.appengine.api.datastore.dev.LocalDatastoreService

    class TestEnv  # :nodoc:
      include AppEngine::ApiProxy::Environment
      
      attr_writer :appid, :version, :email, :admin, :logged_in
      attr_writer :auth_domain, :request_namespace, :default_namespace
      
      def initialize
        @appid = "test"
        @version = "1.0"
        @auth_domain = "gmail.com"
      end
      
      def getAppId
        @appid
      end
      
      def getVersionId
        @version
      end
      
      def getEmail
        @email
      end
      
      def isLoggedIn
        @logged_in
      end
      
      def isAdmin
        @admin
      end
      
      def getAuthDomain
        @auth_domain
      end
      
      def getRequestNamespace
        @request_namespace
      end
      
      def getDefaultNamespace
        @default_namespace
      end
      
      def setDefaultNamespace(s)
        @default_namespace = s
      end      
    end
    
    class << self
      def install_test_env
        env = TestEnv.new
        ApiProxy::setEnvironmentForCurrentThread(env)
        env
      end
      
      def factory
        @factory ||= ApiProxyLocalFactory.new
      end
      
      def app_dir
        file = factory.getApplicationDirectory
        file && file.path
      end
      
      def app_dir=(dir)
        factory.setApplicationDirectory(java.io.File.new(dir))
      end
      
      # Force all datastore operations to use an in-memory datastore.
      def install_test_datastore
        self.app_dir = '.' if app_dir.nil?
        delegate = factory.create
        delegate.set_property(
            LocalDatastoreService::NO_STORAGE_PROPERTY, "true")
        delegate.set_property(
            LocalDatastoreService::MAX_QUERY_LIFETIME_PROPERTY,
            java.lang.Integer::MAX_VALUE.to_s)
        delegate.set_property(
            LocalDatastoreService::MAX_TRANSACTION_LIFETIME_PROPERTY,
            java.lang.Integer::MAX_VALUE.to_s)
        ApiProxy::setDelegate(delegate)
        delegate
      end
      
      def install_api_stubs
        self.app_dir = '.' if app_dir.nil?
        delegate = factory.create
        ApiProxy::setDelegate(delegate)
        delegate
      end
      
    end

  end
end