require %(json)
require %(date)
require %(options_by_example)
require %(open-uri)

require './cache'
require './client'
require './extensions'


# This script does a tremendous job, really tremendous. It goes to twitter,
# gets all the Grok conversations-every one of them-and it pulls down the
# images too. Very efficient, very powerful, people are saying it’s one of
# the best little scripts they’ve seen for grabbing conversations. Nobody
# downloads Grok conversations better than this script, believe me.

flags = OptionsByExample.read(DATA).parse(ARGV)

username = flags.fetch(:user) { 'default' }
partition = flags.fetch(:partition) { Date.today.iso8601 }

cookie_fname = "my_cookie_#{username}.txt"
cache_fname = "my_cache_#{username}.sqlite"

if flags.include_list_partitions?
  cache = Cache.new cache_fname, partition
  partitions = cache.list_partitions

  if partitions.empty?
    puts "No partitions found in #{cache_fname}"
  else
    partitions.each { |each| puts each }
  end

  exit
end

if flags.include_drop_partition?
  cache = Cache.new cache_fname, partition
  target = flags.get(:drop_partition)
  removed = cache.drop_partition! target
  puts "Dropped partition #{target} from #{cache_fname} (#{removed} rows deleted)"
  exit
end

if flags.include_random?
  files = Dir.glob('images/*').select { it =~ /(jpg|png)$/ }
  selection = files.sample(25) # choose a uniform sample of n=25
  puts selection.each { |fname| system('open', fname) }
  exit
end

grok = Client.new cookie_fname, cache_fname, partition, flags

if flags.include_mark?
  grok.cache.mark_as_stale flags.get(:mark)
  puts "Marked the url as stale, expect it to reload this time"
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

  image_urls.each do |url|

    filename = "#{conversation["conversation_id"]}_#{url[/\d+$/]}_#{grok.hashed_user_id}.jpg"
    old_fname = "images/#{filename}"
    fname = "#{project_folder}/#{filename}"

    FileUtils.mkdir_p(project_folder)
    File.rename(old_fname, fname) if File.exist?(old_fname) && !File.exist?(fname)

    next if File.exist?(fname)
    puts "  downloading #{fname} ..."
    IO.copy_stream(URI.open(url, grok.cookie), fname)
  end
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
  -v, --verbose             Print each URL when it is fetched from the network

The script expects a file named "my_cookie_username.txt" containing three
lines: auth_token, ct0 and twid. These values authenticate the session.

Images are stored in the "images" directory and API responses are cached
in a sqlite database for reasons. Cache entries are scoped to the selected
partition, so the default cache only lasts for one day.

The mapping file is a plain hash from conversation id to folder.
Use null to skip downloads for a conversation.
