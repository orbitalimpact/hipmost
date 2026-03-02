#!/usr/bin/env ruby
# hipmost.rb — HipChat → Mattermost migration
#
# Usage:
#   ruby hipmost.rb audit          EXPORT_PATH                      analyze export, produce mapping YAML
#   ruby hipmost.rb generate       EXPORT_PATH --map FILE            generate JSONL from approved mapping
#   ruby hipmost.rb generate       EXPORT_PATH --map FILE --dry-run
#   ruby hipmost.rb import         OUTPUT.zip                        run mmctl import
#   ruby hipmost.rb import_one     EXPORT_PATH --map FILE --room 'Room Name'
#                                                                    atomic: generate + import + verify one room
#   ruby hipmost.rb import_dm      EXPORT_PATH --map FILE --pair 'user1,user2'
#                                                                    atomic: generate + import + verify one DM pair
#   ruby hipmost.rb fix_attachments EXPORT_PATH --map FILE [--room 'Room Name']
#                                                                    re-import posts that carry file attachments
#
# Requires: pg gem, HIPMOST_DB_URL (or MATTERMOST_DB_URL) in ~/.hipmost-env

require 'pg'
require 'json'
require 'yaml'
require 'date'
require 'time'
require 'fileutils'
require 'set'
require 'shellwords'

def load_env!
  f = File.expand_path('~/.hipmost-env')
  # fall back to the old mm-search name if the new one isn't present
  f = File.expand_path('~/.mm-search-env') unless File.file?(f)
  return unless File.file?(f)
  File.read(f).each_line do |ln|
    ln = ln.strip
    next if ln.empty? || ln.start_with?('#')
    if ln =~ /\Aexport\s+([A-Za-z_]\w*)=(.*)\z/
      k, v = $1, $2.strip
      v = v[1..-2] if (v.start_with?('"') && v.end_with?('"')) ||
                       (v.start_with?("'") && v.end_with?("'"))
      ENV[k] ||= v
    end
  end
end

load_env!

MM_MAX_MSG    = 16_383
MM_MAX_FILE   = 52_428_800  # 50 MB per Mattermost default limit
MM_MAX_PIXELS = 24_385_536

EMOJI_MAP = {
  '(thumbsup)' => ':+1:', '(thumbsdown)' => ':-1:',
  '(heart)' => ':heart:', '(broken)' => ':broken_heart:',
  '(smile)' => ':smile:', '(laugh)' => ':laughing:',
  '(wink)' => ':wink:', '(tongue)' => ':stuck_out_tongue:',
  '(cool)' => ':sunglasses:', '(cry)' => ':cry:',
  '(angry)' => ':angry:', '(devil)' => ':smiling_imp:',
  '(embarrassed)' => ':flushed:', '(oops)' => ':sweat:',
  '(yawn)' => ':sleepy:', '(pokerface)' => ':no_mouth:',
  '(worried)' => ':worried:', '(surprised)' => ':astonished:',
  '(star)' => ':star:', '(flag)' => ':flag_white:',
  '(cash)' => ':moneybag:', '(beer)' => ':beer:',
  '(coffee)' => ':coffee:', '(cake)' => ':cake:',
  '(music)' => ':musical_note:', '(trophy)' => ':trophy:',
  '(bug)' => ':bug:', '(book)' => ':book:',
  '(clock)' => ':clock3:', '(mail)' => ':email:',
  '(phone)' => ':telephone_receiver:', '(check)' => ':white_check_mark:',
  '(cross)' => ':x:', '(question)' => ':question:',
  '(exclamation)' => ':exclamation:', '(warning)' => ':warning:',
  '(lock)' => ':lock:', '(key)' => ':key:',
  '(pencil)' => ':pencil:', '(idea)' => ':bulb:',
  '(facepalm)' => ':man_facepalming:', '(shrug)' => ':shrug:',
  '(poop)' => ':poop:', '(party)' => ':tada:',
  '(clap)' => ':clap:', '(fire)' => ':fire:',
  '(wave)' => ':wave:', '(ok)' => ':ok_hand:',
  '(pray)' => ':pray:', '(muscle)' => ':muscle:',
  '(eyes)' => ':eyes:', '(100)' => ':100:',
  '(boom)' => ':boom:', '(rocket)' => ':rocket:',
}.freeze

# =================================================================
# HipChat export reader (read-only)
# =================================================================
module HC
  def self.load_rooms(path)
    f = File.join(path, 'rooms.json')
    abort "Missing #{f}" unless File.exist?(f)
    JSON.parse(File.read(f)).map { |r| r['Room'] }
  end

  def self.load_users(path)
    f = File.join(path, 'users.json')
    abort "Missing #{f}" unless File.exist?(f)
    JSON.parse(File.read(f)).map { |u| u['User'] }
  end

  def self.load_room_msgs(path, room_id)
    f = File.join(path, 'rooms', room_id.to_s, 'history.json')
    return [] unless File.exist?(f)
    raw = JSON.parse(File.read(f))
    raw.select { |m| m['UserMessage'] || m['PrivateUserMessage'] }
        .map { |m| m['UserMessage'] || m['PrivateUserMessage'] }
  end

  def self.load_dm_files(path, user_id)
    f = File.join(path, 'users', user_id.to_s, 'history.json')
    return {} unless File.exist?(f)
    raw = JSON.parse(File.read(f))
    result = {}
    raw.each do |m|
      pm = m['PrivateUserMessage']
      next unless pm
      sender_id  = pm.dig('sender', 'id') || pm['sender']
      receiver_id = pm['receiver']
      partner = (sender_id.to_i == user_id.to_i) ? receiver_id.to_s : sender_id.to_s
      result[partner] ||= []
      result[partner] << pm
    end
    result
  end

  def self.room_files(path, room_id)
    dir = File.join(path, 'rooms', room_id.to_s, 'files')
    return [] unless Dir.exist?(dir)
    Dir.glob(File.join(dir, '**', '*')).select { |f| File.file?(f) }
  end

  def self.ts_to_ms(timestamp_str)
    dt = DateTime.parse(timestamp_str)
    (dt.to_time.to_f * 1000).to_i
  end
end

# =================================================================
# Mattermost DB queries (read-only outside of import verification)
# =================================================================
module MM
  def self.conn
    @conn ||= begin
      url = ENV['HIPMOST_DB_URL'] || ENV['MATTERMOST_DB_URL']
      abort "HIPMOST_DB_URL not set (add to ~/.hipmost-env)" unless url && !url.empty?
      PG::Connection.new(url)
    end
  end

  def self.teams
    conn.exec("SELECT id, name, displayname FROM teams ORDER BY name").to_a
  end

  def self.channels(team_id = nil)
    if team_id
      conn.exec_params(
        "SELECT c.id, c.name, c.displayname, c.type, c.teamid,
                (SELECT COUNT(*) FROM posts p WHERE p.channelid = c.id) as post_count
         FROM channels c WHERE c.teamid = $1 ORDER BY c.displayname", [team_id]
      ).to_a
    else
      conn.exec(
        "SELECT c.id, c.name, c.displayname, c.type, c.teamid, t.name as team_name,
                (SELECT COUNT(*) FROM posts p WHERE p.channelid = c.id) as post_count
         FROM channels c LEFT JOIN teams t ON c.teamid = t.id
         WHERE c.type IN ('O','P')
         ORDER BY t.name, c.displayname"
      ).to_a
    end
  end

  def self.users
    conn.exec(
      "SELECT id, username, email, firstname, lastname, deleteat
       FROM users ORDER BY username"
    ).to_a
  end

  def self.post_range(channel_id)
    r = conn.exec_params(
      "SELECT COUNT(*) as cnt,
              MIN(createat) as min_ts,
              MAX(createat) as max_ts
       FROM posts WHERE channelid = $1 AND deleteat = 0", [channel_id]
    ).first
    { count: r['cnt'].to_i, min_ts: r['min_ts'].to_i, max_ts: r['max_ts'].to_i }
  end

  def self.posts_in_range(channel_id, min_ts, max_ts)
    conn.exec_params(
      "SELECT p.createat, p.message, u.username
       FROM posts p JOIN users u ON p.userid = u.id
       WHERE p.channelid = $1 AND p.createat >= $2 AND p.createat <= $3
       AND p.deleteat = 0
       ORDER BY p.createat",
      [channel_id, min_ts, max_ts]
    ).to_a
  end

  def self.dm_channels
    conn.exec(
      "SELECT c.id, c.name, c.type,
              (SELECT COUNT(*) FROM posts p WHERE p.channelid = c.id) as post_count
       FROM channels c WHERE c.type = 'D'
       ORDER BY post_count DESC"
    ).to_a
  end
end

# =================================================================
# Name matching / sanitization
# =================================================================
def sanitize_name(name)
  name = name.downcase
  name = name.gsub(/[^a-z0-9\-]/, '-')
  name = name.gsub(/-+/, '-')
  name = name.sub(/\A-/, '').sub(/-\z/, '')
  name = "x#{name}" if name =~ /\A\d/
  name.empty? ? 'unnamed' : name
end

def fuzzy_match(hc_name, mm_channels)
  san = sanitize_name(hc_name)
  best = nil
  best_score = 0
  best_match = nil

  mm_channels.each do |ch|
    if ch['name'] == san
      return { channel: ch, score: 1.0, match: 'exact' }
    end

    if ch['displayname']&.downcase == hc_name.downcase
      return { channel: ch, score: 0.95, match: 'display' }
    end

    dn = (ch['displayname'] || '').downcase
    cn = ch['name'].downcase
    if dn.include?(hc_name.downcase) || hc_name.downcase.include?(dn)
      score = [dn.length, hc_name.length].min.to_f / [dn.length, hc_name.length].max
      if score > best_score
        best = ch
        best_score = score
        best_match = 'substring'
      end
    end
    if cn.include?(san) || san.include?(cn)
      score = [cn.length, san.length].min.to_f / [cn.length, san.length].max
      if score > best_score
        best = ch
        best_score = score
        best_match = 'partial'
      end
    end
  end

  return nil if best_score < 0.5
  { channel: best, score: best_score, match: best_match }
end

# =================================================================
# AUDIT subcommand
# =================================================================
def cmd_audit(export_path)
  abort "Export path not found: #{export_path}" unless Dir.exist?(export_path)

  $stderr.puts "Loading HipChat export from #{export_path}..."
  hc_rooms = HC.load_rooms(export_path)
  hc_users = HC.load_users(export_path)

  $stderr.puts "Querying Mattermost database..."
  mm_teams       = MM.teams
  mm_all_channels = MM.channels
  mm_users       = MM.users
  mm_dms         = MM.dm_channels

  # --- User mapping ---
  $stderr.puts "Matching #{hc_users.size} HipChat users -> Mattermost users..."
  user_map = {}
  hc_users.each do |hu|
    hc_name  = hu['mention_name']
    hc_email = hu['email'] || ''
    hc_id    = hu['id']
    deleted  = hu['is_deleted']

    mm_match = mm_users.find { |mu| mu['email']&.downcase == hc_email.downcase }
    mm_match ||= mm_users.find { |mu| mu['username']&.downcase == hc_name&.downcase }

    user_map[hc_name] = {
      'hc_id'      => hc_id,
      'hc_email'   => hc_email,
      'hc_type'    => hu['account_type'],
      'hc_deleted' => deleted,
      'mm_user'    => mm_match ? mm_match['username'] : nil,
      'mm_email'   => mm_match ? mm_match['email'] : nil,
      'action'     => deleted ? 'skip' : (mm_match ? 'map' : 'create'),
    }
  end

  # --- Room mapping ---
  $stderr.puts "Matching #{hc_rooms.size} HipChat rooms -> Mattermost channels..."
  room_map = {}
  hc_rooms.each do |hr|
    name    = hr['name']
    rid     = hr['id']
    priv    = hr['privacy']
    members = hr['members'] || []

    msgs      = HC.load_room_msgs(export_path, rid)
    files     = HC.room_files(export_path, rid)
    msg_count = msgs.size

    suggested = nil
    mm_team   = nil
    mm_posts  = 0

    mm_all_channels.each do |ch|
      m = fuzzy_match(name, [ch])
      next unless m && m[:score] >= 0.8
      suggested = "#{ch['team_name']}:#{ch['name']}"
      mm_team   = ch['team_name']
      mm_posts  = ch['post_count'].to_i
      break if m[:score] >= 0.95
    end

    action = if suggested && mm_posts > 0 && (mm_posts - msg_count).abs <= 5
               'skip'   # counts match — probably already imported
             elsif suggested && mm_posts > 0
               'merge'  # channel exists, counts differ
             elsif suggested
               'merge'
             else
               'new'
             end

    room_map[name] = {
      'hc_id'       => rid,
      'hc_msgs'     => msg_count,
      'hc_files'    => files.size,
      'hc_privacy'  => priv,
      'hc_members'  => members.size,
      'suggested'   => suggested,
      'mm_posts'    => mm_posts,
      'action'      => action,
    }
  end

  # --- DM inventory ---
  $stderr.puts "Scanning DMs..."
  dm_summary    = {}
  total_dm_msgs = 0
  hc_users.each do |hu|
    next if hu['account_type'] == 'guest'
    dms   = HC.load_dm_files(export_path, hu['id'])
    count = dms.values.sum(&:size)
    total_dm_msgs += count
    dm_summary[hu['mention_name']] = {
      'hc_id'         => hu['id'],
      'conversations' => dms.size,
      'messages'      => count,
    }
  end

  mm_dm_count = mm_dms.sum { |d| d['post_count'].to_i }

  audit = {
    'generated'  => Time.now.strftime('%Y-%m-%d %H:%M:%S'),
    'export_path' => export_path,
    'summary' => {
      'hc_rooms'      => hc_rooms.size,
      'hc_users'      => hc_users.size,
      'hc_room_msgs'  => room_map.values.sum { |r| r['hc_msgs'] },
      'hc_dm_msgs'    => total_dm_msgs,
      'mm_teams'      => mm_teams.size,
      'mm_channels'   => mm_all_channels.size,
      'mm_dm_posts'   => mm_dm_count,
    },
    'users' => user_map,
    'rooms' => room_map,
    'dms' => {
      'import_dms'          => 'verify',
      'total_hc_dm_msgs'    => total_dm_msgs,
      'existing_mm_dm_posts' => mm_dm_count,
      'per_user'            => dm_summary,
    },
  }

  out_file = 'hipmost-audit.yaml'
  File.write(out_file, audit.to_yaml)
  $stderr.puts "\nAudit written to #{out_file}"
  $stderr.puts "Review and edit actions (map/skip/merge/new/create) before running generate."

  puts "=== HipChat Export Audit ==="
  puts
  puts "Users: #{hc_users.size} HC -> #{user_map.count { |_, v| v['action'] == 'map' }} mapped, " \
       "#{user_map.count { |_, v| v['action'] == 'create' }} need creating, " \
       "#{user_map.count { |_, v| v['action'] == 'skip' }} skipped"
  puts
  puts "Rooms:"
  room_map.each do |name, info|
    tag = case info['action']
          when 'skip'  then "\e[32mSKIP\e[0m"
          when 'merge' then "\e[33mMERGE\e[0m"
          when 'new'   then "\e[36mNEW\e[0m"
          else info['action']
          end
    sug = info['suggested'] || '(no match)'
    puts "  [#{tag}] #{name} (#{info['hc_msgs']} msgs, #{info['hc_files']} files) -> #{sug} (#{info['mm_posts']} MM posts)"
  end
  puts
  puts "DMs: #{total_dm_msgs} HC messages, #{mm_dm_count} existing MM DM posts"
  puts "     import_dms: verify (edit in YAML to 'yes' or 'no')"
end

# =================================================================
# Message conversion
# =================================================================
def convert_msg(text)
  return '' if text.nil? || text.empty?

  if text.start_with?('/code')
    return "```\n#{text[6..]}\n```"
  end

  if text.start_with?('/quote')
    return text[7..].to_s.lines.map { |l| "> #{l}" }.join
  end

  EMOJI_MAP.each { |hc, mm| text = text.gsub(hc, mm) }

  text
end

# split oversized messages at word boundaries
def split_msg(text)
  return [text] if text.length <= MM_MAX_MSG
  chunks = []
  rest = text
  while rest.length > MM_MAX_MSG
    idx = rest.rindex(' ', MM_MAX_MSG) || MM_MAX_MSG
    chunks << rest[0...idx]
    rest = rest[idx..].lstrip
  end
  chunks << rest unless rest.empty?
  chunks
end

# =================================================================
# GENERATE subcommand
# =================================================================
def cmd_generate(export_path, map_file, dry_run: false)
  abort "Export path not found: #{export_path}" unless Dir.exist?(export_path)
  abort "Mapping file not found: #{map_file}"   unless File.exist?(map_file)

  y          = YAML.load_file(map_file)
  dm_cfg     = y['dms'] || {}
  mp         = load_approved_mapping(map_file)
  umap       = mp[:umap]
  uid_map    = mp[:uid_map]
  hc_users   = HC.load_users(export_path)
  hc_by_id   = hc_users.each_with_object({}) { |u, h| h[u['id']] = u }

  out_dir    = 'hipmost-output'
  attach_dir = File.join(out_dir, 'data')
  unless dry_run
    FileUtils.mkdir_p(out_dir)
    FileUtils.mkdir_p(attach_dir)
  end

  lines = []
  lines << { type: 'version', version: 1 }

  teams_emitted    = Set.new
  channels_emitted = Set.new
  users_emitted    = Set.new

  skipped  = 0
  imported = 0

  # --- Process rooms ---
  mp[:rooms].each do |room|
    next if room['action'] == 'skip'
    target = room['target']
    next unless target

    team, channel = target.split(':', 2)
    room_name = room['hc_name']
    unless team && channel
      $stderr.puts "WARN: bad target '#{target}' for #{room_name}, skipping"
      next
    end

    rid = room['hc_id']

    unless teams_emitted.include?(team)
      lines << { type: 'team', team: { name: team, display_name: team.gsub('-', ' ').split.map(&:capitalize).join(' '), type: 'I' } }
      teams_emitted << team
    end

    ch_key = "#{team}:#{channel}"
    unless channels_emitted.include?(ch_key)
      ch_type = room['type'] || 'O'
      disp    = room['display_name'] || room_name
      lines << {
        type: 'channel',
        channel: { team: team, name: channel, display_name: disp, type: ch_type }
      }
      channels_emitted << ch_key
    end

    msgs = HC.load_room_msgs(export_path, rid)
    $stderr.puts "Processing #{room_name}: #{msgs.size} messages -> #{ch_key}"

    # for merge targets, load existing timestamps to skip duplicates
    existing_by_ts = {}
    if room['action'] == 'merge' && !dry_run
      mm_ch = MM.channels.find { |c| c['name'] == channel && c['team_name'] == team }
      if mm_ch
        range = MM.post_range(mm_ch['id'])
        if range[:count] > 0
          posts = MM.posts_in_range(mm_ch['id'], range[:min_ts], range[:max_ts])
          posts.each { |p| existing_by_ts[p['createat'].to_i] = p }
          $stderr.puts "  Loaded #{posts.size} existing posts for collision check"
        end
      end
    end

    msgs.each do |msg|
      sender_id   = msg.dig('sender', 'id') || msg['sender_id']
      sender_name = uid_map[sender_id]
      unless sender_name
        mn = msg.dig('sender', 'mention_name')
        sender_name = umap[mn] if mn
      end
      next unless sender_name

      unless users_emitted.include?(sender_name)
        hu = hc_by_id[sender_id]
        if hu
          lines << {
            type: 'user',
            user: {
              username: sender_name,
              email: hu['email'] || "#{sender_name}@imported.local",
            }
          }
        end
        users_emitted << sender_name
      end

      ts   = HC.ts_to_ms(msg['timestamp'])
      text = convert_msg(msg['message'] || '')
      next if text.strip.empty?

      if room['action'] == 'merge' && existing_by_ts.key?(ts)
        skipped += 1
        next
      end

      if room['action'] == 'merge' && !existing_by_ts.empty?
        nearby = existing_by_ts.select { |t, _| (t - ts).abs < 5000 }
        unless nearby.empty?
          $stderr.puts "  NEAR-COLLISION: #{sender_name} at #{Time.at(ts / 1000)} (#{nearby.size} nearby posts)"
        end
      end

      attachments = nil
      apath = msg['attachment_path'] || msg.dig('attachment', 'path')
      if apath && !apath.empty?
        att_src = File.join(export_path, 'rooms', rid.to_s, 'files', apath)
        if File.exist?(att_src)
          sz = File.size(att_src)
          if sz <= MM_MAX_FILE
            att_rel = File.join('rooms', rid.to_s, 'files', apath)
            unless dry_run
              dest_full = File.join(out_dir, 'data', att_rel)
              FileUtils.mkdir_p(File.dirname(dest_full))
              FileUtils.cp(att_src, dest_full)
            end
            attachments = [{ path: att_rel }]
          else
            $stderr.puts "  SKIP attachment (#{sz} bytes > #{MM_MAX_FILE}): #{att_src}"
          end
        end
      end

      chunks = split_msg(text)
      chunks.each_with_index do |chunk, i|
        post = {
          type: 'post',
          post: {
            team: team, channel: channel, user: sender_name,
            message: chunk, create_at: ts + i,
          }
        }
        post[:post][:attachments] = attachments if attachments && i == 0
        lines << post
        imported += 1
      end
    end
  end

  # --- Process DMs ---
  if dm_cfg['import_dms'] == 'yes' || dm_cfg['import_dms'] == true
    $stderr.puts "\nProcessing DMs..."

    dm_channels_emitted = Set.new

    hc_users.each do |hu|
      next if hu['account_type'] == 'guest'
      sender_mm = umap[hu['mention_name']]
      next unless sender_mm

      dms = HC.load_dm_files(export_path, hu['id'])
      dms.each do |partner_id, msgs|
        partner_hu = hc_by_id[partner_id.to_i]
        next unless partner_hu
        partner_mm = umap[partner_hu['mention_name']]
        next unless partner_mm

        members = [sender_mm, partner_mm].sort

        next if sender_mm == partner_mm
        next if sender_mm != members.first

        ch_key = members.join('__')
        unless dm_channels_emitted.include?(ch_key)
          lines << {
            type: 'direct_channel',
            direct_channel: { members: members }
          }
          dm_channels_emitted << ch_key
        end

        msgs.each do |msg|
          sender_id  = msg.dig('sender', 'id') || msg['sender_id']
          msg_sender = uid_map[sender_id]
          next unless msg_sender

          ts   = HC.ts_to_ms(msg['timestamp'])
          text = convert_msg(msg['message'] || '')
          next if text.strip.empty?

          chunks = split_msg(text)
          chunks.each_with_index do |chunk, i|
            lines << {
              type: 'direct_post',
              direct_post: {
                channel_members: members,
                user: msg_sender,
                message: chunk,
                create_at: ts + i,
              }
            }
            imported += 1
          end
        end
      end
    end
  end

  # --- Write JSONL ---
  if dry_run
    puts "DRY RUN -- would generate #{lines.size} JSONL lines"
    puts "  Imported: #{imported} posts"
    puts "  Skipped:  #{skipped} (duplicate timestamp)"
    return
  end

  jsonl_file = File.join(out_dir, 'import.jsonl')

  type_order = %w[version team channel user post direct_channel direct_post]
  lines.sort_by! { |l| type_order.index(l[:type].to_s) || 99 }

  File.open(jsonl_file, 'w') { |f| lines.each { |l| f.puts(JSON.generate(l)) } }

  $stderr.puts "\nGenerated #{jsonl_file}"
  $stderr.puts "  Total lines:    #{lines.size}"
  $stderr.puts "  Posts imported: #{imported}"
  $stderr.puts "  Posts skipped:  #{skipped}"

  zip_file = 'hipmost-output.zip'
  ok = system("cd #{Shellwords.escape(out_dir)} && zip -r ../#{Shellwords.escape(zip_file)} . -x '.*'")
  abort "zip failed" unless ok
  $stderr.puts "Packaged: #{zip_file}"
end

# =================================================================
# IMPORT subcommand
# =================================================================
def cmd_import(zip_file)
  abort "Zip file not found: #{zip_file}" unless File.exist?(zip_file)

  mmctl = '/opt/mattermost/bin/mmctl'
  abort "mmctl not found at #{mmctl}" unless File.exist?(mmctl)

  $stderr.puts "Importing #{zip_file}..."
  exec("#{mmctl} import process --bypass-upload #{Shellwords.escape(zip_file)} --local")
end

# =================================================================
# Shared: load approved mapping YAML (rooms_skip / rooms_merge / rooms_new format)
# =================================================================
def load_approved_mapping(map_file)
  y = YAML.load_file(map_file)
  umap = {}; uid_map = {}; uemails = {}; uactions = {}
  (y['users'] || []).each do |u|
    next if u['action'] == 'skip'
    mm = u['mm'] || u['hc']
    umap[u['hc']] = mm
    uid_map[u['hc_id']] = mm
    uemails[mm] ||= u['email'] if u['email']
    uactions[mm] ||= u['action']
  end

  rooms = []
  (y['rooms_skip']  || []).each { |r| rooms << r.merge('action' => 'skip')  }
  (y['rooms_merge'] || []).each { |r| rooms << r.merge('action' => 'merge') }
  (y['rooms_new']   || []).each { |r| rooms << r.merge('action' => 'new')   }

  { umap: umap, uid_map: uid_map, emails: uemails, actions: uactions, rooms: rooms }
end

# =================================================================
# IMPORT_ONE — atomic single-room import + verify
# =================================================================
def cmd_import_one(export_path, map_file, room_name)
  abort "Export path not found: #{export_path}" unless Dir.exist?(export_path)
  abort "Mapping file not found: #{map_file}"   unless File.exist?(map_file)

  mp   = load_approved_mapping(map_file)
  room = mp[:rooms].find { |r| r['hc_name'].downcase == room_name.downcase }
  abort "Room '#{room_name}' not found in mapping" unless room
  abort "Room '#{room_name}' is SKIP"               if room['action'] == 'skip'

  target = room['target']
  abort "No target for '#{room_name}'" unless target
  team, ch_name = target.split(':', 2)
  abort "Bad target '#{target}'" unless team && ch_name

  rid = room['hc_id']
  act = room['action']
  puts "=== IMPORT ONE: #{room['hc_name']} ==="
  puts "  #{act.upcase} -> #{target}"

  hc_users  = HC.load_users(export_path)
  hc_by_id  = hc_users.each_with_object({}) { |u, h| h[u['id']] = u }
  msgs      = HC.load_room_msgs(export_path, rid)
  puts "  HC messages: #{msgs.size}"

  # existing emails in MM — used for mapped users so we don't overwrite
  mm_emails = {}
  MM.conn.exec("SELECT username, email FROM users").each { |r| mm_emails[r['username']] = r['email'] }

  # pre-import snapshot (merge only)
  pre_count  = 0
  existing_ts = Set.new
  if act == 'merge'
    row = MM.conn.exec_params(
      "SELECT c.id FROM channels c JOIN teams t ON c.teamid=t.id WHERE t.name=$1 AND c.name=$2",
      [team, ch_name]
    ).first
    if row
      rng       = MM.post_range(row['id'])
      pre_count = rng[:count]
      puts "  MM pre-import: #{pre_count} posts"
      if rng[:count] > 0
        MM.posts_in_range(row['id'], rng[:min_ts], rng[:max_ts]).each { |p| existing_ts << p['createat'].to_i }
      end
    end
  end

  work = "/tmp/hipmost-#{rid}"
  FileUtils.rm_rf(work)
  FileUtils.mkdir_p(work)

  lines = [{ type: 'version', version: 1 }]
  lines << { type: 'team', team: { name: team, display_name: team.gsub('-', ' ').split.map(&:capitalize).join(' '), type: 'I' } }

  ch_type = room['type'] || 'O'
  disp    = room['display_name'] || room['hc_name']
  lines << { type: 'channel', channel: { team: team, name: ch_name, display_name: disp, type: ch_type } }

  seen       = Set.new
  skipped    = 0
  imported   = 0
  post_lines = []
  att_q      = []

  msgs.each do |msg|
    sid    = msg.dig('sender', 'id') || msg['sender_id']
    sender = mp[:uid_map][sid]
    sender ||= mp[:umap][msg.dig('sender', 'mention_name')] if msg.dig('sender', 'mention_name')
    next unless sender

    unless seen.include?(sender)
      email = if mp[:actions][sender] == 'map'
                mm_emails[sender] || mp[:emails][sender] || "#{sender}@imported.local"
              else
                mp[:emails][sender] || hc_by_id[sid]&.dig('email') || "#{sender}@imported.local"
              end
      lines << { type: 'user', user: { username: sender, email: email } }
      seen << sender
    end

    ts   = HC.ts_to_ms(msg['timestamp'])
    text = convert_msg(msg['message'] || '')
    next if text.strip.empty?

    if act == 'merge' && existing_ts.include?(ts)
      skipped += 1
      next
    end

    att   = nil
    apath = msg['attachment_path'] || msg.dig('attachment', 'path')
    if apath && !apath.empty?
      src = File.join(export_path, 'rooms', rid.to_s, 'files', apath)
      if File.exist?(src) && File.size(src) <= MM_MAX_FILE
        rel = File.join('rooms', rid.to_s, 'files', apath)
        att = [{ path: rel }]
        att_q << [src, File.join(work, 'data', rel)]
      end
    end

    split_msg(text).each_with_index do |chunk, i|
      pl = { type: 'post', post: { team: team, channel: ch_name, user: sender, message: chunk, create_at: ts + i } }
      pl[:post][:attachments] = att if att && i == 0
      post_lines << pl
      imported += 1
    end
  end

  lines.concat(post_lines)
  puts "  Import: #{imported} posts, skip: #{skipped} dups"

  if imported == 0
    puts "  Nothing to import."
    FileUtils.rm_rf(work)
    return
  end

  File.open(File.join(work, 'import.jsonl'), 'w') { |f| lines.each { |l| f.puts JSON.generate(l) } }
  att_q.each { |s, d| FileUtils.mkdir_p(File.dirname(d)); FileUtils.cp(s, d) }

  zip = "/tmp/hipmost-#{rid}.zip"
  File.delete(zip) if File.exist?(zip)
  ok = system("cd #{Shellwords.escape(work)} && zip -qr #{Shellwords.escape(zip)} . -x '.*'")
  abort "zip failed" unless ok
  puts "  Zip: #{zip} (#{(File.size(zip) / 1024.0).round(1)} KB)"

  mmctl = '/opt/mattermost/bin/mmctl'
  abort "mmctl not found" unless File.exist?(mmctl)
  out = `#{mmctl} import process --bypass-upload #{Shellwords.escape(zip)} --local 2>&1`
  abort "FAIL: mmctl:\n#{out}" unless $?.success?
  puts "  mmctl: #{out.strip}"

  jid = out[/([0-9a-z]{26})/, 1]
  if jid
    puts "  Job: #{jid}"
    60.times do |i|
      sleep 2
      js = `#{mmctl} import job show #{jid} 2>&1`
      if js =~ /success/i
        puts "  Job OK"
        break
      end
      abort "FAIL: job:\n#{js}" if js =~ /error|failed/i
      puts "  Waiting... (#{(i + 1) * 2}s)" if i % 5 == 4
    end
  else
    puts "  No job ID parsed, waiting 15s..."
    sleep 15
  end

  puts "\n=== VERIFY ==="
  v = MM.conn.exec_params(
    "SELECT c.id FROM channels c JOIN teams t ON c.teamid=t.id WHERE t.name=$1 AND c.name=$2",
    [team, ch_name]
  ).first
  abort "FAIL: #{target} not found after import" unless v

  cnt = MM.conn.exec_params(
    "SELECT COUNT(*) as n FROM posts WHERE channelid=$1 AND deleteat=0", [v['id']]
  ).first['n'].to_i

  ok = true
  puts "  #{target}: #{cnt} posts"

  if act == 'merge'
    exp = pre_count + imported
    puts "  Pre: #{pre_count}, expected >= #{exp}"
    if cnt >= exp
      puts "  PASS: count OK"
    else
      puts "  FAIL: count LOW (got #{cnt}, expected >= #{exp})"
      ok = false
    end
  else
    if cnt >= imported
      puts "  PASS: count OK"
    else
      puts "  FAIL: count LOW (got #{cnt}, expected >= #{imported})"
      ok = false
    end
  end

  puts "  Samples:"
  MM.conn.exec_params(
    "SELECT p.message, p.createat, u.username FROM posts p JOIN users u ON p.userid=u.id
     WHERE p.channelid=$1 AND p.deleteat=0 ORDER BY p.createat LIMIT 3", [v['id']]
  ).each do |s|
    puts "    [#{Time.at(s['createat'].to_i / 1000)}] #{s['username']}: #{s['message'][0..80]}"
  end

  if act == 'merge' && pre_count > 0
    max_old_ts = existing_ts.max
    old = MM.conn.exec_params(
      "SELECT COUNT(*) as n FROM posts WHERE channelid=$1 AND deleteat=0 AND createat <= $2",
      [v['id'], max_old_ts]
    ).first['n'].to_i
    if old >= pre_count
      puts "  PASS: existing posts intact (#{old} found, was #{pre_count})"
    else
      puts "  FAIL: existing posts damaged (was #{pre_count}, now #{old})"
      ok = false
    end
  end

  if act == 'new' && room['members']
    puts "  Adding members..."
    room['members'].each do |u|
      r = `#{mmctl} channel users add #{Shellwords.escape("#{team}:#{ch_name}")} #{Shellwords.escape(u)} 2>&1`
      puts "    #{u}: #{r.strip}"
    end
  end

  FileUtils.rm_rf(work)
  File.delete(zip) if File.exist?(zip)
  puts "\n=== #{ok ? 'PASS' : 'FAIL'}: #{room['hc_name']} -> #{target} ==="
  exit(1) unless ok
end

# =================================================================
# IMPORT_DM — atomic single DM pair import + verify
# =================================================================
def cmd_import_dm(export_path, map_file, pair_str)
  abort "Export path not found: #{export_path}" unless Dir.exist?(export_path)
  abort "Mapping file not found: #{map_file}"   unless File.exist?(map_file)

  mp       = load_approved_mapping(map_file)
  mm1, mm2 = pair_str.split(',').map(&:strip)
  abort "need exactly two usernames: --pair user1,user2" unless mm1 && mm2

  if mm1 == mm2
    puts "Self-DM (#{mm1}) -- skipping"
    return
  end

  members  = [mm1, mm2].sort
  hc_users = HC.load_users(export_path)
  hc_by_id = hc_users.each_with_object({}) { |u, h| h[u['id']] = u }

  mm_to_hc = {}
  hc_users.each do |hu|
    mm_user = mp[:uid_map][hu['id']] || mp[:umap][hu['mention_name']]
    next unless mm_user
    (mm_to_hc[mm_user] ||= []) << hu['id']
  end

  hc_ids_1 = (mm_to_hc[mm1] || []).uniq
  hc_ids_2 = (mm_to_hc[mm2] || []).uniq
  abort "No HC users map to '#{mm1}'" if hc_ids_1.empty?
  abort "No HC users map to '#{mm2}'" if hc_ids_2.empty?

  puts "=== IMPORT DM: #{mm1} <-> #{mm2} ==="

  all_msgs    = []
  seen        = Set.new
  hc_ids_2_set = hc_ids_2.to_set

  hc_ids_1.each do |uid|
    f = File.join(export_path, 'users', uid.to_s, 'history.json')
    next unless File.exist?(f)
    JSON.parse(File.read(f)).each do |m|
      pm = m['PrivateUserMessage']
      next unless pm
      next if seen.include?(pm['id'])
      sid = pm.dig('sender', 'id')
      rid = pm.dig('receiver', 'id')
      partner_id = (sid == uid) ? rid : sid
      next unless hc_ids_2_set.include?(partner_id)
      seen << pm['id']
      all_msgs << pm
    end
  end

  all_msgs.sort_by! { |m| m['timestamp'] }
  puts "  HC messages: #{all_msgs.size}"

  if all_msgs.empty?
    puts "  No messages found."
    return
  end

  pre_count   = 0
  existing_ts = Set.new
  mm_uids     = {}
  [mm1, mm2].each do |u|
    r = MM.conn.exec_params("SELECT id FROM users WHERE username=$1", [u]).first
    mm_uids[u] = r['id'] if r
  end

  dm_ch_id = nil
  if mm_uids[mm1] && mm_uids[mm2]
    ch_name = [mm_uids[mm1], mm_uids[mm2]].sort.join('__')
    row = MM.conn.exec_params("SELECT id FROM channels WHERE name=$1 AND type='D'", [ch_name]).first
    if row
      dm_ch_id  = row['id']
      rng       = MM.post_range(dm_ch_id)
      pre_count = rng[:count]
      puts "  MM pre-import: #{pre_count} posts"
      if rng[:count] > 0
        MM.posts_in_range(dm_ch_id, rng[:min_ts], rng[:max_ts]).each { |p| existing_ts << p['createat'].to_i }
      end
    else
      puts "  MM pre-import: 0 posts (new DM channel)"
    end
  else
    puts "  MM pre-import: 0 posts (user(s) not yet in MM)"
  end

  tag  = members.join('-')
  work = "/tmp/hipmost-dm-#{tag}"
  FileUtils.rm_rf(work)
  FileUtils.mkdir_p(work)

  mm_emails = {}
  MM.conn.exec("SELECT username, email FROM users").each { |r| mm_emails[r['username']] = r['email'] }

  lines = [{ type: 'version', version: 1 }]
  [mm1, mm2].each do |u|
    email = mm_emails[u] || mp[:emails][u] || "#{u}@imported.local"
    lines << { type: 'user', user: { username: u, email: email } }
  end
  lines << { type: 'direct_channel', direct_channel: { members: members } }

  skipped    = 0
  imported   = 0
  post_lines = []

  all_msgs.each do |msg|
    sid    = msg.dig('sender', 'id')
    sender = mp[:uid_map][sid] || mp[:umap][msg.dig('sender', 'mention_name')]
    next unless sender

    ts   = HC.ts_to_ms(msg['timestamp'])
    text = convert_msg(msg['message'] || '')
    next if text.strip.empty?

    if existing_ts.include?(ts)
      skipped += 1
      next
    end

    att   = nil
    apath = msg['attachment_path'] || msg.dig('attachment', 'path')
    if apath && !apath.empty?
      src = nil
      hc_ids_1.each do |uid|
        c = File.join(export_path, 'users', uid.to_s, 'files', apath)
        if File.exist?(c) && File.size(c) <= MM_MAX_FILE
          src = c
          break
        end
      end
      if src
        rel  = File.join('dm-files', tag, apath)
        att  = [{ path: rel }]
        dest = File.join(work, 'data', rel)
        FileUtils.mkdir_p(File.dirname(dest))
        FileUtils.cp(src, dest)
      end
    end

    split_msg(text).each_with_index do |chunk, i|
      pl = {
        type: 'direct_post',
        direct_post: {
          channel_members: members,
          user: sender,
          message: chunk,
          create_at: ts + i,
        }
      }
      pl[:direct_post][:attachments] = att if att && i == 0
      post_lines << pl
      imported += 1
    end
  end

  lines.concat(post_lines)
  puts "  Import: #{imported} posts, skip: #{skipped} dups"

  if imported == 0
    puts "  Nothing to import (all duplicates)."
    FileUtils.rm_rf(work)
    return
  end

  File.open(File.join(work, 'import.jsonl'), 'w') { |f| lines.each { |l| f.puts JSON.generate(l) } }

  zip = "/tmp/hipmost-dm-#{tag}.zip"
  File.delete(zip) if File.exist?(zip)
  ok = system("cd #{Shellwords.escape(work)} && zip -qr #{Shellwords.escape(zip)} . -x '.*'")
  abort "zip failed" unless ok
  puts "  Zip: #{zip} (#{(File.size(zip) / 1024.0).round(1)} KB)"

  mmctl = '/opt/mattermost/bin/mmctl'
  abort "mmctl not found" unless File.exist?(mmctl)
  out = `#{mmctl} import process --bypass-upload #{Shellwords.escape(zip)} --local 2>&1`
  abort "FAIL: mmctl:\n#{out}" unless $?.success?
  puts "  mmctl: #{out.strip}"

  jid = out[/([0-9a-z]{26})/, 1]
  if jid
    puts "  Job: #{jid}"
    120.times do |i|
      sleep 2
      js = `#{mmctl} import job show #{jid} 2>&1`
      if js =~ /success/i
        puts "  Job OK"
        break
      end
      abort "FAIL: job:\n#{js}" if js =~ /error|failed/i
      puts "  Waiting... (#{(i + 1) * 2}s)" if i % 5 == 4
    end
  else
    puts "  No job ID parsed, waiting 15s..."
    sleep 15
  end

  puts "\n=== VERIFY ==="
  ok = true

  [mm1, mm2].each do |u|
    next if mm_uids[u]
    r = MM.conn.exec_params("SELECT id FROM users WHERE username=$1", [u]).first
    mm_uids[u] = r['id'] if r
  end

  if mm_uids[mm1] && mm_uids[mm2]
    ch_name = [mm_uids[mm1], mm_uids[mm2]].sort.join('__')
    v = MM.conn.exec_params("SELECT id FROM channels WHERE name=$1 AND type='D'", [ch_name]).first
    if v
      cnt = MM.conn.exec_params(
        "SELECT COUNT(*) as n FROM posts WHERE channelid=$1 AND deleteat=0", [v['id']]
      ).first['n'].to_i

      puts "  #{mm1} <-> #{mm2}: #{cnt} posts"
      exp = pre_count + imported
      puts "  Pre: #{pre_count}, expected >= #{exp}"
      if cnt >= exp
        puts "  PASS: count OK"
      else
        puts "  FAIL: count LOW (got #{cnt}, expected >= #{exp})"
        ok = false
      end

      puts "  Samples:"
      MM.conn.exec_params(
        "SELECT p.message, p.createat, u.username FROM posts p JOIN users u ON p.userid=u.id
         WHERE p.channelid=$1 AND p.deleteat=0 ORDER BY p.createat LIMIT 3", [v['id']]
      ).each do |s|
        puts "    [#{Time.at(s['createat'].to_i / 1000)}] #{s['username']}: #{s['message'][0..80]}"
      end

      if pre_count > 0 && !existing_ts.empty?
        max_old_ts = existing_ts.max
        old = MM.conn.exec_params(
          "SELECT COUNT(*) as n FROM posts WHERE channelid=$1 AND deleteat=0 AND createat <= $2",
          [v['id'], max_old_ts]
        ).first['n'].to_i
        if old >= pre_count
          puts "  PASS: existing posts intact (#{old} found, was #{pre_count})"
        else
          puts "  FAIL: existing posts damaged (was #{pre_count}, now #{old})"
          ok = false
        end
      end
    else
      puts "  WARN: DM channel not found after import"
      ok = false
    end
  else
    missing = [mm1, mm2].reject { |u| mm_uids[u] }
    puts "  WARN: cannot verify -- user(s) #{missing.join(', ')} not found in MM"
    ok = false
  end

  FileUtils.rm_rf(work)
  File.delete(zip) if File.exist?(zip)
  puts "\n=== #{ok ? 'PASS' : 'FAIL'}: #{mm1} <-> #{mm2} ==="
  exit(1) unless ok
end

# =================================================================
# FIX_ATTACHMENTS — re-import posts that carry file attachments
# Mattermost matches by channel+create_at and attaches files to existing posts
# =================================================================
def cmd_fix_attachments(export_path, map_file, room_filter: nil)
  abort "Export path not found: #{export_path}" unless Dir.exist?(export_path)
  abort "Mapping file not found: #{map_file}"   unless File.exist?(map_file)

  mp           = load_approved_mapping(map_file)
  hc_rooms     = HC.load_rooms(export_path)
  hc_users     = HC.load_users(export_path)
  hc_user_by_id = hc_users.each_with_object({}) { |u, h| h[u['id']] = u }

  umap    = mp[:umap].dup
  uid_map = mp[:uid_map].dup

  all_rooms = mp[:rooms].select { |r| r['action'] != 'skip' }.select do |r|
    rid       = r['hc_id']
    files_dir = File.join(export_path, 'rooms', rid.to_s, 'files')
    Dir.exist?(files_dir) && Dir.glob(File.join(files_dir, '**', '*')).any? { |f| File.file?(f) }
  end

  if room_filter
    all_rooms.select! { |r| r['hc_name'].strip.downcase == room_filter.strip.downcase }
    abort "Room '#{room_filter}' not found or has no files" if all_rooms.empty?
  end

  puts "=== FIX ATTACHMENTS: #{all_rooms.size} rooms with files ==="

  all_rooms.each do |r|
    rid      = r['hc_id']
    tgt      = r['target']
    team, channel = tgt.split(':')
    room_name = r['hc_name']

    msgs     = HC.load_room_msgs(export_path, rid)
    att_msgs = msgs.select { |m| ap = m['attachment_path']; ap && !ap.to_s.strip.empty? }
    next if att_msgs.empty?

    puts "\n--- #{room_name} (#{tgt}): #{att_msgs.size} attachment messages ---"

    work = "/tmp/hipmost-fixatt-#{rid}"
    FileUtils.rm_rf(work)
    FileUtils.mkdir_p(work)

    lines = [{ type: 'version', version: 1 }]
    lines << { type: 'team', team: { name: team, display_name: team.upcase, type: 'I' } }

    ch_type = (r['type'] || 'P') == 'O' ? 'O' : 'P'
    lines << { type: 'channel', channel: { team: team, name: channel, display_name: room_name, type: ch_type } }

    users_emitted = Set.new
    post_lines    = []
    files_copied  = 0
    files_skipped = 0

    att_msgs.each do |msg|
      sender_id = msg.dig('sender', 'id') || msg['sender_id']
      sender_name = uid_map[sender_id]
      unless sender_name
        mn = msg.dig('sender', 'mention_name')
        sender_name = umap[mn] if mn
      end
      next unless sender_name

      unless users_emitted.include?(sender_name)
        hu    = hc_user_by_id[sender_id]
        email = hu ? (hu['email'] || "#{sender_name}@imported.local") : "#{sender_name}@imported.local"
        lines << { type: 'user', user: { username: sender_name, email: email } }
        users_emitted << sender_name
      end

      ts   = HC.ts_to_ms(msg['timestamp'])
      text = convert_msg(msg['message'] || '')
      text = '(file)' if text.strip.empty?

      apath   = msg['attachment_path']
      att_src = File.join(export_path, 'rooms', rid.to_s, 'files', apath)
      next unless File.exist?(att_src)
      sz = File.size(att_src)
      if sz > MM_MAX_FILE
        files_skipped += 1
        next
      end

      att_rel   = File.join('rooms', rid.to_s, 'files', apath)
      dest_full = File.join(work, 'data', att_rel)
      FileUtils.mkdir_p(File.dirname(dest_full))
      FileUtils.cp(att_src, dest_full)
      files_copied += 1

      split_msg(text).each_with_index do |chunk, i|
        pl = {
          type: 'post',
          post: { team: team, channel: channel, user: sender_name, message: chunk, create_at: ts + i }
        }
        pl[:post][:attachments] = [{ path: att_rel }] if i == 0
        post_lines << pl
      end
    end

    lines.concat(post_lines)
    puts "  Files: #{files_copied} copied, #{files_skipped} skipped (oversized)"
    puts "  Posts: #{post_lines.size}"

    if files_copied == 0
      puts "  Nothing to import."
      FileUtils.rm_rf(work)
      next
    end

    File.open(File.join(work, 'import.jsonl'), 'w') { |f| lines.each { |l| f.puts JSON.generate(l) } }

    zip = "/tmp/hipmost-fixatt-#{rid}.zip"
    File.delete(zip) if File.exist?(zip)
    ok = system("cd #{Shellwords.escape(work)} && zip -qr #{Shellwords.escape(zip)} . -x '.*'")
    abort "zip failed" unless ok
    puts "  Zip: #{(File.size(zip) / 1048576.0).round(1)} MB"

    mmctl = '/opt/mattermost/bin/mmctl'
    out   = `#{mmctl} import process --bypass-upload #{Shellwords.escape(zip)} --local 2>&1`
    abort "FAIL: mmctl:\n#{out}" unless $?.success?
    puts "  mmctl: #{out.strip}"

    jid = out[/([0-9a-z]{26})/, 1]
    if jid
      120.times do |i|
        sleep 2
        js = `#{mmctl} import job show #{jid} 2>&1`
        if js =~ /success/i
          puts "  Job OK"
          break
        end
        abort "FAIL: job:\n#{js}" if js =~ /error|failed/i
        puts "  Waiting... (#{(i + 1) * 2}s)" if i % 5 == 4
      end
    else
      sleep 15
    end

    ch_row = MM.conn.exec_params(
      "SELECT c.id FROM channels c JOIN teams t ON c.teamid=t.id WHERE t.name=$1 AND c.name=$2",
      [team, channel]
    ).first
    if ch_row
      fi_cnt = MM.conn.exec_params(
        "SELECT count(*) as n FROM fileinfo fi JOIN posts p ON fi.postid=p.id
         WHERE p.channelid=$1 AND fi.deleteat=0",
        [ch_row['id']]
      ).first['n'].to_i
      if fi_cnt >= files_copied
        puts "  PASS: #{fi_cnt} files in MM (expected >= #{files_copied})"
      else
        puts "  WARN: #{fi_cnt} files in MM (expected >= #{files_copied})"
      end
    end

    FileUtils.rm_rf(work)
    File.delete(zip) if File.exist?(zip)
  end

  puts "\n=== DONE ==="
end

# =================================================================
# CLI routing
# =================================================================
cmd = ARGV.shift
case cmd
when 'audit'
  path = ARGV.shift || abort("Usage: hipmost.rb audit EXPORT_PATH")
  cmd_audit(path)

when 'generate'
  path     = ARGV.shift || abort("Usage: hipmost.rb generate EXPORT_PATH --map FILE")
  map_file = nil
  dry_run  = false
  while (arg = ARGV.shift)
    case arg
    when '--map'      then map_file = ARGV.shift
    when '--dry-run'  then dry_run  = true
    end
  end
  abort("--map FILE required") unless map_file
  cmd_generate(path, map_file, dry_run: dry_run)

when 'import'
  zip = ARGV.shift || abort("Usage: hipmost.rb import FILE.zip")
  cmd_import(zip)

when 'import_one'
  path      = ARGV.shift || abort("Usage: hipmost.rb import_one EXPORT_PATH --map FILE --room 'Room Name'")
  map_file  = nil
  room_name = nil
  while (arg = ARGV.shift)
    case arg
    when '--map'  then map_file  = ARGV.shift
    when '--room' then room_name = ARGV.shift
    end
  end
  abort("--map FILE required")            unless map_file
  abort("--room 'Room Name' required")    unless room_name
  cmd_import_one(path, map_file, room_name)

when 'import_dm'
  path     = ARGV.shift || abort("Usage: hipmost.rb import_dm EXPORT_PATH --map FILE --pair 'user1,user2'")
  map_file = nil
  pair_str = nil
  while (arg = ARGV.shift)
    case arg
    when '--map'  then map_file = ARGV.shift
    when '--pair' then pair_str = ARGV.shift
    end
  end
  abort("--map FILE required")                    unless map_file
  abort("--pair 'user1,user2' required")          unless pair_str
  cmd_import_dm(path, map_file, pair_str)

when 'fix_attachments'
  path        = ARGV.shift || abort("Usage: hipmost.rb fix_attachments EXPORT_PATH --map FILE [--room 'Room Name']")
  map_file    = nil
  room_filter = nil
  while (arg = ARGV.shift)
    case arg
    when '--map'  then map_file    = ARGV.shift
    when '--room' then room_filter = ARGV.shift
    end
  end
  abort("--map FILE required") unless map_file
  cmd_fix_attachments(path, map_file, room_filter: room_filter)

else
  $stderr.puts <<~HELP
    hipmost.rb -- HipChat to Mattermost migration

    Commands:
      audit          EXPORT_PATH                           analyze export, write hipmost-audit.yaml
      generate       EXPORT_PATH --map FILE                generate JSONL from approved mapping
      generate       EXPORT_PATH --map FILE --dry-run      preview without writing files
      import         OUTPUT.zip                            run mmctl import (bulk)
      import_one     EXPORT_PATH --map FILE --room NAME    import + verify one room atomically
      import_dm      EXPORT_PATH --map FILE --pair u1,u2   import + verify one DM pair atomically
      fix_attachments EXPORT_PATH --map FILE [--room NAME] re-attach files to already-imported posts

    Setup:
      Create ~/.hipmost-env with:
        export HIPMOST_DB_URL=postgres://user:pass@host/mattermost

    Typical workflow:
      ruby hipmost.rb audit /path/to/hipchat-export
      # edit hipmost-audit.yaml -> convert to approved mapping.yaml
      ruby hipmost.rb import_one /path/to/hipchat-export --map mapping.yaml --room 'Engineering'
      # repeat for each room, then DMs
  HELP
  exit 1
end
