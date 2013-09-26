# Copyright 2011-2013 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"). You
# may not use this file except in compliance with the License. A copy of
# the License is located at
#
#     http://aws.amazon.com/apache2.0/
#
# or in the "license" file accompanying this file. This file is
# distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF
# ANY KIND, either express or implied. See the License for the specific
# language governing permissions and limitations under the License.

require 'time'
require 'digest/sha1'
require 'openssl'

module Aws
  module Signers
    class V4

      # @param [Credentials] credentials
      # @param [String] service_name The name used by the service in
      #   signing signature version 4 requests.  This is generally
      #   the endpoint prefix.
      # @param [String] region The region (e.g. 'us-west-1') the request
      #   will be made to.
      def initialize(credentials, service_name, region)
        @credentials = credentials
        @service_name = service_name
        @region = region
      end

      # @param [Seahorse::Client::Http::Request] request
      # @return [Seahorse::Client::Http::Request] the signed request.
      def sign(request)
        datetime = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
        request.headers['X-Amz-Date'] = datetime
        request.headers['Host'] = request.endpoint.host
        request.headers['X-Amz-Security-Token'] = credentials.session_token if
          credentials.session_token
        request.headers['X-Amz-Content-Sha256'] ||= hexdigest(request.body)
        request.headers['Authorization'] = authorization(request, datetime)
        request
      end

      def authorization(request, datetime)
        parts = []
        parts << "AWS4-HMAC-SHA256 Credential=#{credentials.access_key_id}/#{credential_scope(datetime)}"
        parts << "SignedHeaders=#{signed_headers(request)}"
        parts << "Signature=#{signature(request, datetime)}"
        parts.join(', ')
      end

      def signature(request, datetime)
        k_secret = credentials.secret_access_key
        k_date = hmac("AWS4" + k_secret, datetime[0,8])
        k_region = hmac(k_date, region)
        k_service = hmac(k_region, service_name)
        k_credentials = hmac(k_service, 'aws4_request')
        hexhmac(k_credentials, string_to_sign(request, datetime))
      end

      def string_to_sign(request, datetime)
        parts = []
        parts << 'AWS4-HMAC-SHA256'
        parts << datetime
        parts << credential_scope(datetime)
        parts << hexdigest(canonical_request(request))
        parts.join("\n")
      end

      def credential_scope(datetime)
        parts = []
        parts << datetime[0,8]
        parts << region
        parts << service_name
        parts << 'aws4_request'
        parts.join("/")
      end

      def canonical_request(request)
        parts = []
        parts << request.http_method
        parts << request.path.split('?', 2)[0] || ''
        parts << request.path.split('?', 2)[1] || ''
        parts << canonical_headers(request) + "\n"
        parts << signed_headers(request)
        parts << request.headers['X-Amz-Content-Sha256']
        parts.join("\n")
      end

      def signed_headers(request)
        to_sign = request.headers.keys.map(&:to_s).map(&:downcase)
        to_sign.delete('authorization')
        to_sign.sort.join(";")
      end

      def canonical_headers(request)
        headers = []
        request.headers.each_pair do |k,v|
          k = k.downcase
          headers << [k,v] unless k == 'authorization'
        end
        headers = headers.sort_by(&:first)
        headers.map{|k,v| "#{k}:#{canonical_header_value(v.to_s)}" }.join("\n")
      end

      def canonical_header_value(value)
        value.match(/^".*"$/) ? value : value.gsub(/\s+/, ' ').strip
      end

      def hexdigest(value)
        digest = Digest::SHA256.new
        if value.respond_to?(:read)
          chunk = nil
          chunk_size = 1024 * 1024 # 1 megabyte
          digest.update(chunk) while chunk = value.read(chunk_size)
          value.rewind
        else
          digest.update(value)
        end
        digest.hexdigest
      end

      def hmac(key, value)
        OpenSSL::HMAC.digest(OpenSSL::Digest::Digest.new('sha256'), key, value)
      end

      def hexhmac(key, value)
        OpenSSL::HMAC.hexdigest(OpenSSL::Digest::Digest.new('sha256'), key, value)
      end

      private

      # @return [Credentials]
      attr_reader :credentials

      # @return [String]
      attr_reader :service_name

      # @return [String]
      attr_reader :region

    end
  end
end