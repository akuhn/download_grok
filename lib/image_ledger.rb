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

    def move_if_folder_changed
      FileUtils.mkdir_p(File.dirname(@fname))
      return unless @old_fname != @fname && File.exist?(@old_fname) && !File.exist?(@fname)

      File.rename(@old_fname, @fname)
      @ledger.instance_variable_get(:@db).execute(
        "UPDATE images SET path = ? WHERE path = ?",
        [@fname, @old_fname]
      )
    end

    def has_been_deleted?
      media_id = @source_url.to_s[/\d+$/]
      !!@ledger.instance_variable_get(:@db).get_first_row(
        "SELECT 1 FROM images WHERE media_id = ? AND status = 'duplicate_delete' LIMIT 1",
        [media_id]
      )
    end

    def exists_on_disk?
      File.exist?(@fname)
    end

    def deduplicate_and_maybe_delete_file
      result = @ledger.check_for_duplicates_and_update_or_insert_rows(
        username: @username,
        conversation_id: @conversation_id,
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

        result = @ledger.check_for_duplicates_and_update_or_insert_rows(
          username: @username,
          conversation_id: @conversation_id,
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

  def find_images_by_name(name)
    @db.execute(
      %{
        SELECT media_id, username, conversation_id, path, status, canonical_media_id
        FROM images
        WHERE path LIKE ?
        ORDER BY path
      },
      ["%#{name}%"]
    )
  end

  def check_for_duplicates_and_update_or_insert_rows(username:, conversation_id:, media_id:, source_path:, path:)
    size_bytes = File.size(source_path)
    md5 = Digest::MD5.file(source_path).hexdigest

    @db.transaction do
      existing = @db.get_first_row("SELECT * FROM images WHERE media_id = ?", [media_id])

      # Same id, new bits? That does not fit.
      # We stop this train before bad records sit.
      if existing && (existing["size_bytes"] != size_bytes || existing["md5"] != md5)
        raise ArgumentError, "media_id #{media_id} already exists with different fingerprint"
      end

      # We scan for twins by hash and size.
      # More than one keeper means surprise.
      canonicals = @db.execute(
        %{
          SELECT media_id, status
          FROM images
          WHERE md5 = ? AND size_bytes = ?
            AND status IN ('unique', 'duplicate_keep')
          ORDER BY media_id
        },
        [md5, size_bytes]
      )
      raise ArgumentError, "multiple canonical rows for fingerprint md5=#{md5} size_bytes=#{size_bytes}" if canonicals.length > 1
      canonical = canonicals.first

      if existing
        # Same id, same bits: we mostly stay.
        # Only point to a keeper when ids split away.
        if canonical && canonical["media_id"] != media_id
          if existing["status"] != "duplicate_delete" || existing["canonical_media_id"] != canonical["media_id"]
            @db.execute(
              "UPDATE images SET status = ?, canonical_media_id = ? WHERE media_id = ?",
              ["duplicate_delete", canonical["media_id"], media_id]
            )
          end
          {
            media_id: media_id,
            status: "duplicate_delete",
            canonical_media_id: canonical["media_id"],
          }
        else
          {
            media_id: media_id,
            status: existing["status"],
            canonical_media_id: existing["canonical_media_id"],
          }
        end
      else
        # Brand-new id: twin means delete, no twin means keep.
        # One insert path, one place to reap.
        if canonical && canonical["status"] != "duplicate_keep"
          @db.execute(
            "UPDATE images SET status = ? WHERE media_id = ?",
            ["duplicate_keep", canonical["media_id"]]
          )
        end

        status = canonical ? "duplicate_delete" : "unique"
        canonical_media_id = canonical && canonical["media_id"]
        @db.execute(
          %{
            INSERT INTO images (
              media_id, username, conversation_id, path,
              size_bytes, md5, status, canonical_media_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          },
          [media_id, username.to_s, conversation_id.to_s, path, size_bytes, md5, status, canonical_media_id]
        )
        { media_id: media_id, status: status, canonical_media_id: canonical_media_id }
      end
    end
  end

end
