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
#
# Ruby interface to the Java ApiProxy.

require 'java'

module AppEngine
  
  import Java.com.google.apphosting.api.ApiProxy
  
  class ApiProxy
    def self.get_app_id
      get_current_environment.getAppId
    end
  
    def self.get_auth_domain
      get_current_environment.getAuthDomain
    end
  end
end

