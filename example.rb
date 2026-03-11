require %(net/http)
require %(uri)
require %(openssl)

require './cache'


url = "https://x.com/i/api/graphql/9Hyh5D4-WXLnExZkONSkZg/GrokHistory?variables=%7B%7D"

def download(url)

  puts "Downloading #{url}"

  uri = URI(url)

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE

  req = Net::HTTP::Get.new(uri)

  req["authorization"] = "Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"
  req["content-type"] = "application/json"
  req["x-csrf-token"] = "86f9839721a063ee07162f096d87ed5f19245ac0f697b3fe4c56bd09b891cc7e8ec445af379274c48adf6f92f26781df478b9fde6c0d72eadb2409b2890f2550f8bd7c21b61d044b0484318e2f41992b"
  req["user-agent"] = "Mozilla/5.0"
  req["x-twitter-active-user"] = "yes"
  req["x-twitter-auth-type"] = "OAuth2Session"
  req["x-twitter-client-language"] = "en-GB"

  req["cookie"] = [
    "auth_token=2d416a96989e2d8fef021eb2707d616cbf1d6f92",
    "ct0=86f9839721a063ee07162f096d87ed5f19245ac0f697b3fe4c56bd09b891cc7e8ec445af379274c48adf6f92f26781df478b9fde6c0d72eadb2409b2890f2550f8bd7c21b61d044b0484318e2f41992b",
    "twid=u%3D1468725167551442945"
  ].join("; ")

  res = http.request(req)
  res.body
end

db = Cache.new 'my_cache.sqlite'

puts db.fetch(url) { download url }