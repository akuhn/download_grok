require %(json)
require %(date)
require %(options_by_example)
require %(open-uri)
require %(tempfile)

require_relative "lib/cache"
require_relative "lib/client"
require_relative "lib/extensions"
require_relative "lib/image_ledger"


# This script does a tremendous job, really tremendous. It goes to twitter,
# gets all the Grok conversations-every one of them-and it pulls down the
# images too. Very efficient, very powerful, people are saying it’s one of
# the best little scripts they’ve seen for grabbing conversations. Nobody
# downloads Grok conversations better than this script, believe me.

flags = OptionsByExample.read(DATA).parse(ARGV)
flags.expect_at_most_one_of :all, :user
flags.expect_at_most_one_of :drop_partition, :list_partitions, :random


if flags.include_random?
  files = Dir.glob('images/*').select { it =~ /(jpg|png)$/ }
  grouped = files.group_by { |fname| fname.split('/').last.split('_').first }
  selection = grouped.values.sample(flags.get :num).map(&:sample)
  selection.each { |fname| system('open', fname) }
  puts selection
  exit
end

partition = flags.fetch(:partition) { Date.today.iso8601 }

def ensure_storage_folders
  %w[config data].each { |dir| Dir.mkdir(dir) unless Dir.exist?(dir) }
end

def find_usernames(flags)
  return [flags.fetch(:user, 'default')] unless flags.include_all?
  Dir.glob("config/cookie_*.txt")
    .map { |it| File.basename(it)[/cookie_(.+)\.txt/, 1] }
    .compact
end

def run_partition_command(cache_fname, partition, flags)
  cache = Cache.new cache_fname, partition

  if flags.include_list_partitions?
    partitions = cache.list_partitions

    if partitions.empty?
      puts "No partitions found in #{cache_fname}"
    else
      partitions.each { |each| puts "  #{each}" }
    end
    return true
  end

  if flags.include_drop_partition?
    target = flags.get(:drop_partition)
    removed = cache.drop_partition! target
    puts "Dropped partition #{target} from #{cache_fname} (#{removed} rows deleted)"
    return true
  end

  false
end

def run_for_user(username, partition, flags)
  cookie_fname = "config/cookie_#{username}.txt"
  cache_fname = "data/cache_#{username}.sqlite"

  unless File.exist?(cookie_fname)
    puts "Skipping #{username}, missing #{cookie_fname}"
    return
  end

  return if run_partition_command(cache_fname, partition, flags)

  grok = Client.new cookie_fname, cache_fname, partition, flags

  if flags.include_mark?
    grok.cache.mark_as_stale flags.get(:mark)
    puts "[#{username}] Marked the url as stale, expect it to reload this time"
  end

  project_map = JSON.parse((File.read('data/project_map.json') rescue "{}"))
  image_ledger = ImageLedger.new("data/downloaded_images.sqlite", username: username, project_map: project_map)

  grok.each_conversation(flags.include_force?) do |conversation|

    messages = conversation.data.grok_conversation_items_by_rest_id.items rescue binding.pry
    puts "  #{messages.length} messages found"

    project_folder = image_ledger.project_folder_for(conversation["conversation_id"])
    if project_folder.nil?
      puts "  Skipping downloads for this conversation"
      next
    elsif project_folder != 'images'
      puts "  Using folder #{project_folder} ..."
    end

    image_urls = (
      messages.flat_map(&'file_attachments').compact.map(&'url') +
      messages.flat_map(&'card_attachments').compact
        .map { JSON.parse it }
        .map(&'imageAttachment.imageUrl').compact
        .reject { it.end_with? "/50" }
        .map { |image_url|
          raise unless image_url =~ /api.*grok.attachment.json\?mediaId=(\d+$)/
          "https://ton.x.com/i/ton/data/grok-attachment/#{$1}"
        }
    )

    image_urls.sort.each do |url|
      image = image_ledger.make_image(url: url, conversation: conversation)
      next if image.has_been_deleted?
      image.move_if_folder_changed

      if image.exists_on_disk?
        image.deduplicate_and_maybe_delete_file if flags.include_deduplicate?
      else
        image.download_and_deduplicate(cookie: grok.cookie)
      end
    end
  end
end

if flags.include_info?
  query = flags.get(:info)
  ledger = ImageLedger.new("data/downloaded_images.sqlite")
  matches = ledger.find_images_by_name(query)

  matches.each do |row|
    media_id = row["media_id"]
    conversation_id = row["conversation_id"]
    puts "path: #{row["path"]}"
    puts "  username: #{row["username"]}"
    puts "  conversation_id: #{conversation_id}"
    puts "  media_id: #{media_id}"
    puts "  canonical_media_id: #{row["canonical_media_id"]}" if row["canonical_media_id"]
    puts "  conversation_url: https://x.com/i/grok?conversation=#{conversation_id}"
    puts "  source_url: https://ton.x.com/i/ton/data/grok-attachment/#{media_id}"
    puts "  status: #{row["status"]}"
    puts
  end

  puts "Found #{matches.length} match#{'es' if matches.length > 1}"

  exit
end

ensure_storage_folders
usernames = find_usernames(flags)
if usernames.empty?
  puts "No cookie files found matching config/cookie_*.txt"
  exit 1
end

usernames.each do |username|
  puts "---- running for #{username} #{'-' * (40 - username.length)}" if usernames.length > 1
  run_for_user(username, partition, flags)
  puts if usernames.length > 1
end


__END__
Download all images from grok conversations on twitter.

Usage: download.rb [options]

Options:
  -u, --user NAME           Use specific cookie and cache files
  -p, --partition NAME      Cache partition to use, defaults to today's date
  -m, --mark URL            Mark a cached response as stale and refetch this time
  -d, --deduplicate         Find duplicate files and move them to trash folder
  -f, --force               Force a full scan, disable incremental updates
  -i, --info FILE           Show information about this image filename
  -a, --all                 Run for every config/cookie_*.txt user
  -r, --random              Open random files from the images folder and exit
  -n, --num NUM             Number of random files (default 10)
  --drop-partition NAME     Delete all cache rows in NAME and exit
  --list-partitions         List all partitions current user and exit
  -v, --verbose             Print each URL when it is fetched from the network

The script expects a file named "config/cookie_username.txt" containing three
lines: auth_token, ct0 and twid. These values authenticate the session.

Images are stored in the "images" directory and API responses are cached
in "data/cache_<username>.sqlite". The image ledger lives in
"data/downloaded_images.sqlite". Cache entries are scoped to the selected
partition, so the default cache only lasts for one day.

The mapping file is a plain hash from conversation id to folder.
It should be placed at "data/project_map.json".
Use null to skip downloads for a conversation.
