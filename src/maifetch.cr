require "http/client"
require "json"
require "option_parser"
require "path"

BASE_URL = "https://maitea.app"

record Config,
  access_token : String?,
  config_file : String?,
  logo_size : Int32,
  score_count : Int32,
  profiles_fixture : String?,
  plays_fixture : String?,
  no_color : Bool

def default_config_path : String
  home = ENV["HOME"]? || "."
  if appdata = ENV["APPDATA"]?
    File.join(appdata, "maifetch.json")
  elsif xdg = ENV["XDG_CONFIG_HOME"]?
    File.join(xdg, "maifetch.json")
  elsif Dir.exists?(File.join(home, "Library", "Application Support"))
    File.join(home, "Library", "Application Support", "maifetch.json")
  else
    File.join(home, ".config", "maifetch.json")
  end
end

def parse_int(value : String?, fallback : Int32) : Int32
  return fallback if value.nil? || value.empty?
  value.to_i? || fallback
end

def read_json_config(path : String) : Hash(String, JSON::Any)
  return Hash(String, JSON::Any).new unless File.exists?(path)
  JSON.parse(File.read(path)).as_h
rescue ex : JSON::ParseException
  raise "could not parse config file #{path}: #{ex.message}"
end

def load_config : Config
  cli_token = nil.as(String?)
  cli_config_file = nil.as(String?)
  cli_logo_size = nil.as(Int32?)
  cli_score_count = nil.as(Int32?)
  profiles_fixture = nil.as(String?)
  plays_fixture = nil.as(String?)
  no_color = false

  OptionParser.parse do |parser|
    parser.banner = "Usage: maifetch [options]"
    parser.on("-a TOKEN", "--access-token=TOKEN", "Access token for the MaiTea account") { |value| cli_token = value }
    parser.on("-t TOKEN", "Access token for the MaiTea account") { |value| cli_token = value }
    parser.on("-l SIZE", "--logo-size=SIZE", "Size of the ASCII logo (<1 disables)") { |value| cli_logo_size = parse_int(value, 20) }
    parser.on("-s COUNT", "--score-count=COUNT", "Amount of recent scores to show (max 12)") { |value| cli_score_count = parse_int(value, 4) }
    parser.on("-c FILE", "--config-file=FILE", "Config file to use") { |value| cli_config_file = value }
    parser.on("--profiles-fixture=FILE", "Read profiles JSON from a fixture file") { |value| profiles_fixture = value }
    parser.on("--plays-fixture=FILE", "Read plays JSON from a fixture file") { |value| plays_fixture = value }
    parser.on("--no-color", "Disable ANSI colors") { no_color = true }
    parser.on("-h", "--help", "Show this help") do
      puts parser
      exit
    end
  end

  config_file = cli_config_file || ENV["MAITEA_CONFIG_FILE"]? || default_config_path
  json_config = read_json_config(config_file)

  file_token = json_config["accessToken"]?.try(&.as_s?)
  file_logo_size = json_config["logoSize"]?.try(&.as_i?)
  file_score_count = json_config["scoreCount"]?.try(&.as_i?)

  logo_size = (file_logo_size || 20).to_i
  score_count = (file_score_count || 4).to_i
  access_token = file_token

  if env_token = ENV["MAITEA_TOKEN"]?
    access_token = env_token
  end
  logo_size = parse_int(ENV["MAITEA_LOGO_SIZE"]?, logo_size)
  score_count = parse_int(ENV["MAITEA_SCORE_COUNT"]?, score_count)

  if cli_token_value = cli_token
    access_token = cli_token_value
  end
  if cli_logo_size_value = cli_logo_size
    logo_size = cli_logo_size_value
  end
  if cli_score_count_value = cli_score_count
    score_count = cli_score_count_value
  end

  unless profiles_fixture && plays_fixture
    raise "access token is required" if access_token.nil? || access_token.try(&.empty?)
  end

  raise "score count cannot be higher than 12" if score_count > 12

  Config.new(
    access_token: access_token,
    config_file: config_file,
    logo_size: logo_size,
    score_count: score_count,
    profiles_fixture: profiles_fixture,
    plays_fixture: plays_fixture,
    no_color: no_color
  )
end

def cyan(text : String, no_color : Bool) : String
  return text if no_color
  "\e[38;2;72;184;200m#{text}\e[0m"
end

def fg(text : String, r : Int32, g : Int32, b : Int32, no_color : Bool) : String
  return text if no_color
  "\e[38;2;#{r};#{g};#{b}m#{text}\e[0m"
end

def bg(text : String, r : Int32, g : Int32, b : Int32, no_color : Bool) : String
  return text if no_color
  "\e[38;2;255;255;255m\e[48;2;#{r};#{g};#{b}m#{text}\e[0m"
end

def difficulty_label(value : String, no_color : Bool) : String
  case value
  when "easy"
    bg("Easy", 69, 174, 255, no_color)
  when "basic"
    bg("Basic", 111, 212, 61, no_color)
  when "advanced"
    bg("Advanced", 248, 183, 9, no_color)
  when "expert"
    bg("Expert", 255, 46, 66, no_color)
  when "master"
    bg("Master", 171, 140, 233, no_color)
  when "remaster", "re:master"
    bg("Re:Master", 207, 114, 237, no_color)
  when "utage"
    bg("Utage", 255, 68, 1, no_color)
  else
    value
  end
end

def rank_label(rank : String, no_color : Bool) : String
  case rank
  when "SSS+"
    fg("S", 255, 200, 54, no_color) + fg("S", 225, 38, 165, no_color) + fg("S", 73, 64, 233, no_color) + fg("+", 21, 203, 148, no_color)
  when "SSS"
    fg("S", 255, 200, 54, no_color) + fg("S", 232, 39, 148, no_color) + fg("S", 18, 195, 144, no_color)
  when "SS+", "SS"
    bg(rank, 143, 71, 33, no_color)
  when "S+", "S"
    bg(rank, 75, 82, 82, no_color)
  when "AAA", "AA", "A"
    fg(rank, 23, 163, 255, no_color)
  else
    rank
  end
end

def wide_to_normal(text : String) : String
  String.build do |io|
    text.each_char do |char|
      codepoint = char.ord
      if codepoint >= 0xFF01 && codepoint <= 0xFF5E
        io << (codepoint - 0xFEE0).chr
      else
        io << char
      end
    end
  end
end

def fetch_json(path : String, token : String) : JSON::Any
  headers = HTTP::Headers{
    "Authorization" => "Bearer #{token}",
    "Content-Type"  => "application/json",
    "Accept"        => "application/json",
  }
  response = HTTP::Client.get("#{BASE_URL}#{path}", headers: headers)
  unless response.success?
    raise "MaiTea API request failed for #{path}: HTTP #{response.status_code}"
  end
  JSON.parse(response.body)
end

def load_collection(path : String?, api_path : String, token : String?) : Array(JSON::Any)
  json = path ? JSON.parse(File.read(path)) : fetch_json(api_path, token.not_nil!)
  data = json["data"]?
  raise "response from #{path || api_path} did not include a data array" unless data
  data.as_a
end

def string_at(json : JSON::Any, *keys : String) : String
  value = keys.reduce(json) { |memo, key| memo[key] }
  value.as_s
rescue
  ""
end

def int_at(json : JSON::Any, *keys : String) : Int32
  value = keys.reduce(json) { |memo, key| memo[key] }
  value.as_i
rescue
  0
end

def nullable_string_at(json : JSON::Any, *keys : String) : String
  value = keys.reduce(json) { |memo, key| memo[key] }
  value.as_s? || ""
rescue
  ""
end

def build_info_lines(profile : JSON::Any, plays : Array(JSON::Any), score_count : Int32, no_color : Bool) : Array(String)
  name = wide_to_normal(string_at(profile, "name"))
  rating = int_at(profile, "rating")
  rating_highest = int_at(profile, "rating_highest")
  total_credits = int_at(profile, "play_stats", "total")

  info = [
    cyan(name, no_color),
    "-" * name.size,
    "#{cyan("ID", no_color)}: #{int_at(profile, "id")}",
    "#{cyan("Rating", no_color)}: #{"%.2f" % (rating / 100.0)} / #{"%.2f" % (rating_highest / 100.0)}",
    "#{cyan("Level", no_color)}: #{int_at(profile, "level")}",
    "#{cyan("Total Credits", no_color)}: #{total_credits}",
    "#{cyan("Recent Scores", no_color)}:",
  ]

  plays.first(score_count).each do |play|
    song_name = string_at(play, "song", "name", "en")
    difficulty = string_at(play, "difficulty_level", "value")
    fc_label = nullable_string_at(play, "full_combo_label")
    info << "  #{song_name}  #{difficulty_label(difficulty, no_color)}"
    info << "  #{string_at(play, "score_formatted")} #{string_at(play, "achievement_formatted")}% #{rank_label(string_at(play, "rank"), no_color)} #{fc_label}".rstrip
    info << ""
  end

  info
end

def logo_lines(icon_url : String, size : Int32, no_color : Bool) : Array(String)
  return [] of String if size <= 0

  width = Math.max(size * 2, 8)
  seed = icon_url.bytes.sum { |byte| byte.to_i }
  chars = " .:-=+*#%@"

  Array.new(size) do |row|
    line = String.build do |io|
      width.times do |col|
        index = ((row * row + col * 3 + seed) % chars.size).to_i
        io << chars[index]
      end
    end
    no_color ? line : fg(line, 72, 184, 200, no_color)
  end
end

def print_combined(info_lines : Array(String), logo : Array(String), logo_size : Int32)
  max_lines = Math.max(info_lines.size, logo.size)
  blank_logo = " " * Math.max(logo_size * 2, 8)

  max_lines.times do |index|
    logo_part = index < logo.size ? logo[index] : blank_logo
    info_part = index < info_lines.size ? info_lines[index] : ""
    puts "#{logo_part}  #{info_part}"
  end
end

def main
  config = load_config
  profiles = load_collection(config.profiles_fixture, "/api/v1/profiles", config.access_token)
  raise "No profiles found" if profiles.empty?

  plays = load_collection(config.plays_fixture, "/api/v1/plays", config.access_token)
  info = build_info_lines(profiles.first, plays, config.score_count, config.no_color)

  if config.logo_size > 0
    icon_url = string_at(profiles.first, "options", "icon", "png")
    print_combined(info, logo_lines(icon_url, config.logo_size, config.no_color), config.logo_size)
  else
    puts info.join('\n')
  end
rescue ex
  STDERR.puts ex.message
  exit 1
end

main
