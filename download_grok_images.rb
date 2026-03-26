require %(json)
require %(date)
require %(options_by_example)
require %(open-uri)
require %(tempfile)

require './cache'
require './client'
require './extensions'
require './image_ledger'


# This script does a tremendous job, really tremendous. It goes to twitter,
# gets all the Grok conversations-every one of them-and it pulls down the
# images too. Very efficient, very powerful, people are saying it’s one of
# the best little scripts they’ve seen for grabbing conversations. Nobody
# downloads Grok conversations better than this script, believe me.

flags = OptionsByExample.read(DATA).parse(ARGV)

if flags.include_random?
  files = Dir.glob('images/*').select { it =~ /(jpg|png)$/ }
  selection = files.sample(25) # choose a uniform sample of n=25
  puts selection.each { |fname| system('open', fname) }
  exit
end

image_ledger = ImageLedger.new("my_downloaded_images.sqlite")
partition = flags.fetch(:partition) { Date.today.iso8601 }

def find_usernames(flags)
  return [flags.fetch(:user, 'default')] unless flags.include_all?
  Dir.glob("my_cookie_*.txt").map { it[/cookie_([a-z]+)/, 1] }
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

def run_for_user(username, partition, flags, image_ledger)
  cookie_fname = "my_cookie_#{username}.txt"
  cache_fname = "my_cache_#{username}.sqlite"
  backfill = flags.include_backfill?

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

  project_map = JSON.parse((File.read('project_map.json') rescue "{}"))

  grok.each_conversation(flags.include_incremental?) do |conversation|

    messages = conversation.data.grok_conversation_items_by_rest_id.items rescue binding.pry
    puts "  #{messages.length} messages found"

    project_folder = project_map.fetch(conversation["conversation_id"], 'images')
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
      media_id = url[/\d+$/]
      filename = "#{conversation["conversation_id"]}_#{media_id}.jpg"
      legacy_filename = "#{conversation["conversation_id"]}_#{media_id}_#{grok.hashed_user_id}.jpg"
      fname = "#{project_folder}/#{filename}"

      FileUtils.mkdir_p(project_folder)

      [
        "#{project_folder}/#{legacy_filename}",
        "images/#{legacy_filename}",
      ].uniq.each do |legacy_path|
        next unless File.exist?(legacy_path)
        next if File.exist?(fname)

        File.rename(legacy_path, fname)
        image_ledger.rename_path(legacy_path, fname)
      end

      next if image_ledger.include_source_url?(url)

      if File.exist?(fname)
        if backfill
          result = image_ledger.record_file_download(
            username: username,
            conversation_id: conversation["conversation_id"],
            source_url: url,
            media_id: media_id,
            source_path: fname,
            path: fname,
          )
          if result.fetch(:status) == "duplicate_delete"
            puts "  duplicate existing image, deleting #{fname}"
            File.delete(fname) if File.exist?(fname)
          end
        end
        next
      end
      puts "  downloading #{fname} ..."

      Tempfile.create([filename, ".tmp"]) do |tmp|
        IO.copy_stream(URI.open(url, grok.cookie), tmp)
        tmp.flush

        result = image_ledger.record_file_download(
          username: username,
          conversation_id: conversation["conversation_id"],
          source_url: url,
          media_id: media_id,
          source_path: tmp.path,
          path: fname,
        )

        if result.fetch(:status) == "duplicate_delete"
          puts "  duplicate image, deleting #{fname}"
          next
        end

        FileUtils.mv(tmp.path, fname)
      end
    end
  end
end

usernames = find_usernames(flags)
if usernames.empty?
  puts "No cookie files found matching my_cookie_*.txt"
  exit 1
end

usernames.each do |username|
  puts "---- running for #{username} #{'-' * (40 - username.length)}" if usernames.length > 1
  run_for_user(username, partition, flags, image_ledger)
  puts if usernames.length > 1
end


__END__
Download all images from grok conversations on twitter.

Usage: download_grok_images.rb [options]

Options:
  -u, --user NAME           Use specific cookie and cache files
  -p, --partition NAME      Cache partition to use, defaults to today's date
  -m, --mark URL            Mark a cached response as stale and refetch this time
  --list-partitions         List all partitions current user and exit
  --drop-partition NAME     Delete all cache rows in NAME and exit
  --random                  Open 25 random files from the images folder and exit
  --incremental             Stop once a conversation response is unchanged
  --backfill                Classify existing files and apply dedupe status/deletion
  --all                     Run for every my_cookie_*.txt user
  -v, --verbose             Print each URL when it is fetched from the network

The script expects a file named "my_cookie_username.txt" containing three
lines: auth_token, ct0 and twid. These values authenticate the session.

Images are stored in the "images" directory and API responses are cached
in a sqlite database for reasons. Cache entries are scoped to the selected
partition, so the default cache only lasts for one day.

The mapping file is a plain hash from conversation id to folder.
Use null to skip downloads for a conversation.
