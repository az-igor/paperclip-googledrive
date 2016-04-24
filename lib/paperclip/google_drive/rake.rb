
require 'google/apis/drive_v2'

module Paperclip
  module GoogleDrive
    module Rake
      extend self

      def authorize
        puts 'Enter client ID:'
        client_id = $stdin.gets.chomp
        puts 'Enter client SECRET:'
        client_secret = $stdin.gets.chomp.strip
#        puts 'Enter SCOPE:'
#        oauth_scope = $stdin.gets.chomp.strip
        oauth_scope = ['https://www.googleapis.com/auth/drive', 'https://www.googleapis.com/auth/userinfo.profile']
        puts 'Enter redirect URI:'
        redirect_uri = $stdin.gets.chomp.strip

        # Create a new API client & load the Google Drive API
        client = Google::Apis::DriveV2::DriveService.new(:application_name => 'ppc-gd', :application_version => PaperclipGoogleDrive::VERSION)

        client.authorization.client_id = client_id
        client.authorization.client_secret = client_secret
        client.authorization.scope = oauth_scope
        client.authorization.redirect_uri = redirect_uri

        # Request authorization
        uri = client.authorization.authorization_uri.to_s
        puts "\nGo to this url:"
        puts client.authorization.authorization_uri.to_s
        puts "\n Accept the authorization request from Google in your browser"

        puts "\n\n\n Google will redirect you to localhost, but just copy the code parameter out of the URL they redirect you to, paste it here and hit enter:\n"

        code = $stdin.gets.chomp.strip
        client.authorization.code = code
        client.authorization.fetch_access_token!

        puts "\nAuthorization completed.\n\n"
        puts "client = Google::APIClient.new"
        puts "client.authorization.client_id = '#{client_id}'"
        puts "client.authorization.client_secret = '#{client_secret}'"
        puts "client.authorization.access_token = '#{client.authorization.access_token}'"
        puts "client.authorization.refresh_token = '#{client.authorization.refresh_token}'"
        puts "\n"
      end

      def authorizeV3
        if Rails.application.config.paperclip_defaults[:client_secrets_path].nil?
          puts "You need to specify a `client_secrets_path` in paperclip config"
          return
        end
        client_secrets_keys_hash = YAML.load_file(Rails.application.config.paperclip_defaults[:client_secrets_path])
        client_id = Google::Auth::ClientId.from_hash(client_secrets_keys_hash)
        token_store = Google::Auth::Stores::FileTokenStore.new(
          file: Paperclip::Storage::GoogleDriveV3::CREDENTIALS_PATH
        )
        authorizer = Google::Auth::UserAuthorizer.new(
          client_id, Paperclip::Storage::GoogleDriveV3::SCOPES, token_store)
        credentials = authorizer.get_credentials('default')
        if credentials.nil?
          url = authorizer.get_authorization_url(
            base_url: Paperclip::Storage::GoogleDriveV3::OOB_URI)
          puts "Open the following URL in the browser and enter the " +
               "resulting code after authorization"
          puts url
          code = $stdin.gets.chomp.strip
          credentials = authorizer.get_and_store_credentials_from_code(
            user_id: 'default', code: code, base_url: Paperclip::Storage::GoogleDriveV3::OOB_URI)
        end
        puts "\nAuthorization completed.\n\n"
        puts "Client id = '#{client_id.id}'"
        puts "Client secret = '#{client_id.secret}'"
      end
    end
  end
end
