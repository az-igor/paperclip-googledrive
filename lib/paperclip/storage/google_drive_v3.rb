require 'active_support/core_ext/hash/keys'
require 'active_support/inflector/methods'
require 'active_support/core_ext/object/blank'
require 'yaml'
require 'erb'
require 'google/apis/drive_v3'
require 'googleauth'
require 'googleauth/stores/file_token_store'

module Paperclip

  module Storage
      # * self.extended(base) add instance variable to attachment on call
      # * url return url to show on site with style options
      # * path(style) return title that used to insert file to store or find it in store
      # * public_url_for title  return url to file if find by title or url to default image if set
      # * search_for_title(title) take title, search in given folder and if it finds a file, return id of a file or nil
      # * metadata_by_id(file_i get file metadata from store, used to back url or find out value of trashed
      # * exists?(style)  check either exists file with title or not
      # * default_image  return url to default url if set in option
      # * find_public_folder return id of Public folder, must be in options
      # return id of Public folder, must be in options
      # * parse_credentials(credenti get credentials from file, hash or path
      # * original_extension  return extension of file

    module GoogleDriveV3

      OOB_URI = 'urn:ietf:wg:oauth:2.0:oob'
      SCOPES = [Google::Apis::DriveV3::AUTH_DRIVE_FILE, Google::Apis::DriveV3::AUTH_DRIVE_APPDATA]
      CREDENTIALS_PATH = File.join(Dir.home, '.credentials',
                                   "drive-ruby-quickstart.yaml")

      def self.extended(base)
        begin
          require 'google-api-client'
        rescue LoadError => e
          e.message << " (You may need to install the google-api-client gem)"
          raise e
        end unless defined?(Google)

        base.instance_eval do
          # @google_drive_credentials = parse_credentials(@options[:CLIENT_SECRETS_PATH] || {})
          @client_secrets_path = @options[:google_drive_credentials]
          @google_drive_options = @options[:google_drive_options] || {}
          google_drive_client # Force validations of credentials
        end
      end
      #
      def flush_writes
        @queued_for_write.each do |style, file|
          if exists?(path(style))
            raise FileExists, "file \"#{path(style)}\" already exists in your Google Drive"
          else
            #upload(style, file) #style file
            client = google_drive_client
            title, mime_type = title_for_file(style), "#{content_type}"
            parent_id = @google_drive_options[:public_folder_id] # folder_id for Public folder
            metadata = {
              :name => title, #if it is no extension, that is a folder and another folder
              :description => 'paperclip file on google drive',
              :mimeType => mime_type
            }
            if parent_id
              metadata[:parents] = [parent_id]
            end
            result = client.create_file(
              metadata,
              fields: 'id, name',
              upload_source: file.binmode
            )
            callback = lambda do |res, err|
              if err
                # Handle error...
                puts err.body
              else
                puts "Permission ID: #{res.id}"
              end
            end
            client.create_permission(result.id, {role: 'reader', type: 'anyone'}, fields: 'id', &callback)
          end
        end
        after_flush_writes
        @queued_for_write = {}
      end
      #
      def flush_deletes
        @queued_for_delete.each do |path|
          Paperclip.log("delete #{path}")
          client = google_drive_client
          file_id = search_for_title(path)
          unless file_id.nil?
            folder_id = find_public_folder
            client.delete_file(file_id)
          end
        end
        @queued_for_delete = []
      end
      #
      def google_drive_client
        @google_api_client ||= begin
          # Initialize the client & Google+ API
          client = Google::Apis::DriveV3::DriveService.new
          client.client_options.application_name = @options[:application_name]
          client.authorization = authorize
          set_public_folder_id(client)
          client
        end
      end

      def url(*args)
        if present?
          style = args.first.is_a?(Symbol) ? args.first : default_style
          options = args.last.is_a?(Hash) ? args.last : {}
          public_url_for(path(style))
        else
          default_image
        end
      end

      def path(style)
        title_for_file(style)
      end

      def title_for_file(style)
        file_name = interpolate(path_options, style)
      end # full title

      def public_url_for title
        searched_id = search_for_title(title) #return id if any or style
        if searched_id.nil? # it finds some file
          default_image
        else
          metadata = metadata_by_id(searched_id)
          metadata[:web_content_link]
        end
      end # url
      # take title, search in given folder and if it finds a file, return id of a file or nil
      def search_for_title(title)
        client = google_drive_client
        result = client.list_files(
          q: "'#{@google_drive_options[:public_folder_id]}' in parents and name = '#{title}'",
          fields: 'files(id)'
        ).to_h
        if result[:files].length > 0
          result[:files][0][:id]
        elsif result[:files].length == 0
          nil
        else
          nil
        end
      end # id or nil

      def metadata_by_id(file_id)
        if file_id.is_a? String
          client = google_drive_client
          result = client.get_file(file_id,
            :fields => "name, id, webContentLink, trashed"
          )
          result.to_h # to_h.class # => Hash
        end
      end

      def exists?(style = default_style)
        return false if not present?
        result_id = search_for_title(path(style))
        if result_id.nil?
          false
        else
          data_hash = metadata_by_id(result_id)
          !data_hash[:trashed] # if trashed -> not exists
        end
      end

      def default_image
        if @google_drive_options[:default_url] #if default image is set
          title = @google_drive_options[:default_url]
          searched_id = search_for_title(title) # id
          metadata = metadata_by_id(searched_id) unless searched_id.nil?
          metadata[:web_content_link]
        else
          'No picture' # ---- ?
        end
      end

      def find_public_folder
        unless @google_drive_options[:public_folder_id]
          raise KeyError, "you must set a Public folder if into options"
        end
        @google_drive_options[:public_folder_id]
      end

      class FileExists < ArgumentError
      end

      class UnauthorizedException < StandardError
      end

      private

        def authorize
          client_secrets_keys_hash = YAML.load_file(@client_secrets_path)
          client_id = Google::Auth::ClientId.from_hash(client_secrets_keys_hash)
          token_store = get_token_store
          authorizer = Google::Auth::UserAuthorizer.new(
            client_id, SCOPES, token_store)
          credentials = authorizer.get_credentials('default')
          if credentials.nil?
            raise UnauthorizedException, 'No credentials available, you need to generate a new one with the rake method.'
          end
          credentials
        end

        def path_options
          @options[:path].respond_to?(:call) ? @options[:path].call(self) : @options[:path]
        end

        # return extension of file
        def original_extension
          File.extname(original_filename)
        end

        def set_public_folder_id(client)
          response = client.list_files(
              q: "name = '#{@google_drive_options[:public_folder]}'",
              fields: 'files(id)'
            )
          if response.files.empty?
            file_metadata = {
              name: @google_drive_options[:public_folder],
              mime_type: 'application/vnd.google-apps.folder'
            }
            file = client.create_file(file_metadata, fields: 'id')
            @google_drive_options[:public_folder_id] = file.id
          end
          @google_drive_options[:public_folder_id] = response.files.first.id
        end

        def get_token_store
          if @google_drive_options[:token_store].respond_to?('call')
             token_store = @google_drive_options[:token_store].call(self)
             unless token_store.is_a? Google::Auth::TokenStore
               token_store = Google::Auth::Stores::FileTokenStore.new(file: CREDENTIALS_PATH)
             end
             token_store
           else
             Google::Auth::Stores::FileTokenStore.new(file: CREDENTIALS_PATH)
           end
        end
    end
  end
end
