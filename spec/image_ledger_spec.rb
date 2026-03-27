require "tempfile"
require "digest"
require_relative "../lib/image_ledger"

RSpec.describe ImageLedger do
  let(:ledger) { ImageLedger.new(":memory:", username: "u") }
  let(:db) { ledger.instance_variable_get(:@db) }

  def with_file(content)
    Tempfile.create(["img", ".jpg"]) do |file|
      file.binmode
      file.write(content)
      file.flush
      yield file.path
    end
  end

  def row(media_id)
    db.get_first_row("SELECT * FROM images WHERE media_id = ?", [media_id])
  end

  def insert_row(media_id:, username:, conversation_id:, path:, size_bytes:, md5:, status:, canonical_media_id:)
    db.execute(
      "INSERT INTO images (media_id, username, conversation_id, path, size_bytes, md5, status, canonical_media_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
      [media_id, username, conversation_id, path, size_bytes, md5, status, canonical_media_id]
    )
  end

  it "keeps a unique existing media row unchanged for matching fingerprint" do
    with_file("same-bits") do |source_path|
      ledger.check_for_duplicates_and_update_or_insert_rows(
        username: "first-user",
        conversation_id: "first-conversation",
        media_id: "m1",
        source_path: source_path,
        path: "images/first.jpg",
      )

      ledger.check_for_duplicates_and_update_or_insert_rows(
        username: "second-user",
        conversation_id: "second-conversation",
        media_id: "m1",
        source_path: source_path,
        path: "images/second.jpg",
      )
    end

    expect(row("m1")["username"]).to eq("first-user")
    expect(row("m1")["conversation_id"]).to eq("first-conversation")
    expect(row("m1")["path"]).to eq("images/first.jpg")
    expect(row("m1")["status"]).to eq("unique")
    expect(row("m1")["canonical_media_id"]).to be_nil
  end

  it "raises when existing media_id has a different fingerprint" do
    with_file("one") do |first|
      ledger.check_for_duplicates_and_update_or_insert_rows(
        username: "user",
        conversation_id: "conversation",
        media_id: "m1",
        source_path: first,
        path: "images/one.jpg",
      )

      with_file("two") do |second|
        expect {
          ledger.check_for_duplicates_and_update_or_insert_rows(
            username: "user",
            conversation_id: "conversation",
            media_id: "m1",
            source_path: second,
            path: "images/two.jpg",
          )
        }.to raise_error(ArgumentError, /different fingerprint/)
      end
    end
  end

  it "sets existing media to duplicate_delete when a different canonical exists" do
    with_file("same-bits") do |source_path|
      md5 = Digest::MD5.file(source_path).hexdigest
      size_bytes = File.size(source_path)

      insert_row(
        media_id: "100",
        username: "u1",
        conversation_id: "c1",
        path: "images/100.jpg",
        size_bytes: size_bytes,
        md5: md5,
        status: "unique",
        canonical_media_id: nil,
      )

      insert_row(
        media_id: "200",
        username: "u2",
        conversation_id: "c2",
        path: "images/200.jpg",
        size_bytes: size_bytes,
        md5: md5,
        status: "duplicate_delete",
        canonical_media_id: nil,
      )

      result = ledger.check_for_duplicates_and_update_or_insert_rows(
        username: "u2",
        conversation_id: "c2",
        media_id: "200",
        source_path: source_path,
        path: "images/200.jpg",
      )

      expect(result).to eq(media_id: "200", status: "duplicate_delete", canonical_media_id: "100")
      expect(row("200")["status"]).to eq("duplicate_delete")
      expect(row("200")["canonical_media_id"]).to eq("100")
      expect(row("200")["username"]).to eq("u2")
      expect(row("200")["conversation_id"]).to eq("c2")
      expect(row("200")["path"]).to eq("images/200.jpg")
    end
  end

  it "raises when fingerprint has more than one canonical row" do
    with_file("same-bits") do |source_path|
      md5 = Digest::MD5.file(source_path).hexdigest
      size_bytes = File.size(source_path)

      insert_row(
        media_id: "100",
        username: "u1",
        conversation_id: "c1",
        path: "images/100.jpg",
        size_bytes: size_bytes,
        md5: md5,
        status: "unique",
        canonical_media_id: nil,
      )

      insert_row(
        media_id: "101",
        username: "u2",
        conversation_id: "c2",
        path: "images/101.jpg",
        size_bytes: size_bytes,
        md5: md5,
        status: "duplicate_keep",
        canonical_media_id: nil,
      )

      expect {
        ledger.check_for_duplicates_and_update_or_insert_rows(
          username: "u3",
          conversation_id: "c3",
          media_id: "300",
          source_path: source_path,
          path: "images/300.jpg",
        )
      }.to raise_error(ArgumentError, /multiple canonical rows/)
    end
  end

  it "marks new media as duplicate_delete when canonical exists" do
    with_file("same-bits") do |source_path|
      first = ledger.check_for_duplicates_and_update_or_insert_rows(
        username: "u1",
        conversation_id: "c1",
        media_id: "100",
        source_path: source_path,
        path: "images/100.jpg",
      )

      second = ledger.check_for_duplicates_and_update_or_insert_rows(
        username: "u2",
        conversation_id: "c2",
        media_id: "200",
        source_path: source_path,
        path: "images/200.jpg",
      )

      expect(first).to eq(media_id: "100", status: "unique", canonical_media_id: nil)
      expect(second).to eq(media_id: "200", status: "duplicate_delete", canonical_media_id: "100")
      expect(row("100")["status"]).to eq("duplicate_keep")
      expect(row("200")["status"]).to eq("duplicate_delete")
      expect(row("200")["canonical_media_id"]).to eq("100")
    end
  end
end
