
require "paperclip/google_drive/rake"

namespace :google_drive do
  desc "Authorize Google Drive account: "
  task :authorize do
    Paperclip::GoogleDrive::Rake.authorize
  end
end

namespace :google_drive_v3 do
  desc "Authorize Google Drive V3 account: "
  task :authorize do
    Paperclip::GoogleDrive::Rake.authorizeV3
  end
end
