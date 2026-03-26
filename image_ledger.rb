require %(sqlite3)
require %(digest)
require %(fileutils)
require %(open-uri)
require %(tempfile)

class ImageLedger
  class Image
    def initialize(ledger:, username:, source_url:, conversation:)
      @ledger = ledger
      @username = username
      @source_url = source_url
      @conversation_id = conversation["conversation_id"]
      @media_id = source_url[/\d+$/]
      raise ArgumentError, "media_id is required in source_url #{source_url.inspect}" unless @media_id
      @filename = "#{@conversation_id}_#{@media_id}.jpg"
      @old_fname = "images/#{@filename}"
      @project_folder = @ledger.project_folder_for(@conversation_id)
      @fname = "#{@project_folder}/#{@filename}"
    end

    def has_been_deleted?
      @ledger.source_was_deleted?(@source_url)
    end

    def move_if_folder_changed
      FileUtils.mkdir_p(File.dirname(@fname))
      return unless @old_fname != @fname && File.exist?(@old_fname) && !File.exist?(@fname)

      File.rename(@old_fname, @fname)
      @ledger.rename_path(@old_fname, @fname)
    end

    def exists_on_disk?
      File.exist?(@fname)
    end

    def deduplicate_and_maybe_delete_file
      result = @ledger.record_file_download(
        username: @username,
        conversation_id: @conversation_id,
        source_url: @source_url,
        media_id: @media_id,
        source_path: @fname,
        path: @fname,
      )

      return result unless result.fetch(:status) == "duplicate_delete"

      trash_fname = File.join("trash", @fname)
      FileUtils.mkdir_p(File.dirname(trash_fname))
      if File.exist?(@fname)
        puts "  duplicate existing image, moving #{@fname} to #{trash_fname}"
        FileUtils.mv(@fname, trash_fname)
      end
      result
    end

    def download_and_deduplicate(cookie:)
      puts "  downloading #{@fname} ..."

      Tempfile.create([@filename, ".tmp"]) do |tmp|
        IO.copy_stream(URI.open(@source_url, cookie), tmp)
        tmp.flush

        result = @ledger.record_file_download(
          username: @username,
          conversation_id: @conversation_id,
          source_url: @source_url,
          media_id: @media_id,
          source_path: tmp.path,
          path: @fname,
        )

        if result.fetch(:status) == "duplicate_delete"
          puts "  duplicate image, skipping #{@fname}"
        else
          FileUtils.mv(tmp.path, @fname)
        end
      end
    end
  end

  def initialize(path, username: nil, project_map: {})
    @db = SQLite3::Database.new(path)
    @db.results_as_hash = true
    @username = username
    @project_map = project_map
    ensure_schema!
  end

  def project_folder_for(conversation_id)
    @project_map.fetch(conversation_id, "images")
  end

  def make_image(url:, conversation:)
    Image.new(
      ledger: self,
      username: @username,
      source_url: url,
      conversation: conversation,
    )
  end

  def record_download(username:, conversation_id:, source_url:, media_id:, path:, size_bytes:, md5:)
    @db.transaction do
      existing = get_image(media_id)
      if existing
        refresh_row(
          media_id: media_id,
          username: username,
          conversation_id: conversation_id,
          path: path,
          size_bytes: size_bytes,
          md5: md5,
        )
        return {
          media_id: media_id,
          status: existing["status"],
          canonical_media_id: existing["canonical_media_id"],
        }
      end

      canonical = find_canonical(md5, size_bytes)
      if canonical
        mark_as_duplicate_keep(canonical["media_id"]) unless canonical["status"] == "duplicate_keep"
        insert_row(
          username: username,
          conversation_id: conversation_id,
          media_id: media_id,
          path: path,
          size_bytes: size_bytes,
          md5: md5,
          status: "duplicate_delete",
          canonical_media_id: canonical["media_id"],
        )
        {
          media_id: media_id,
          status: "duplicate_delete",
          canonical_media_id: canonical["media_id"],
        }
      else
        insert_row(
          username: username,
          conversation_id: conversation_id,
          media_id: media_id,
          path: path,
          size_bytes: size_bytes,
          md5: md5,
          status: "unique",
          canonical_media_id: nil,
        )
        { media_id: media_id, status: "unique", canonical_media_id: nil }
      end
    end
  end

  def record_file_download(username:, conversation_id:, source_url:, media_id:, source_path:, path:)
    record_download(
      username: username,
      conversation_id: conversation_id,
      source_url: source_url,
      media_id: media_id,
      path: path,
      size_bytes: File.size(source_path),
      md5: Digest::MD5.file(source_path).hexdigest,
    )
  end

  def get_image(media_id)
    @db.get_first_row("SELECT * FROM images WHERE media_id = ?", [media_id])
  end

  def get_images_for_fingerprint(md5, size_bytes)
    @db.execute(
      "SELECT * FROM images WHERE md5 = ? AND size_bytes = ? ORDER BY media_id",
      [md5, size_bytes]
    )
  end

  def include_source_url?(source_url)
    !!@db.get_first_row(
      "SELECT media_id FROM images WHERE media_id = ? LIMIT 1",
      [source_url.to_s[/\d+$/]]
    )
  end

  def source_was_deleted?(source_url)
    media_id = source_url[/\d+$/]

    row = @db.get_first_row(
      "SELECT media_id FROM images WHERE media_id = ? AND status = 'duplicate_delete' LIMIT 1",
      [media_id]
    )
    !!row
  end

  def rename_path(old_path, new_path)
    return 0 if old_path == new_path

    @db.execute(
      "UPDATE images SET path = ? WHERE path = ?",
      [new_path, old_path]
    )
    @db.changes
  end

  private

  def ensure_schema!
    @db.execute %{
      CREATE TABLE IF NOT EXISTS images (
        media_id TEXT PRIMARY KEY,
        username TEXT NOT NULL,
        conversation_id TEXT,
        path TEXT NOT NULL,
        size_bytes INTEGER NOT NULL,
        md5 TEXT NOT NULL,
        status TEXT NOT NULL,
        canonical_media_id TEXT
      )
    }

    @db.execute %{
      CREATE INDEX IF NOT EXISTS images_md5_size_bytes
      ON images(md5, size_bytes)
    }

    @db.execute %{
      CREATE INDEX IF NOT EXISTS images_username
      ON images(username)
    }
  end

  def find_canonical(md5, size_bytes)
    @db.get_first_row(
      %{
        SELECT media_id, status
        FROM images
        WHERE md5 = ? AND size_bytes = ?
          AND status IN ('unique', 'duplicate_keep')
        ORDER BY media_id
        LIMIT 1
      },
      [md5, size_bytes]
    )
  end

  def mark_as_duplicate_keep(media_id)
    @db.execute(
      "UPDATE images SET status = ? WHERE media_id = ?",
      ["duplicate_keep", media_id]
    )
  end

  def insert_row(username:, conversation_id:, media_id:, path:, size_bytes:, md5:, status:, canonical_media_id:)
    @db.execute(
      %{
        INSERT INTO images (
          media_id, username, conversation_id, path,
          size_bytes, md5, status, canonical_media_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      },
      [media_id, username.to_s, conversation_id.to_s, path, size_bytes, md5, status, canonical_media_id]
    )
  end

  def refresh_row(media_id:, username:, conversation_id:, path:, size_bytes:, md5:)
    @db.execute(
      %{
        UPDATE images
        SET username = ?, conversation_id = ?, path = ?, size_bytes = ?, md5 = ?
        WHERE media_id = ?
      },
      [username.to_s, conversation_id.to_s, path, size_bytes, md5, media_id]
    )
  end

end
