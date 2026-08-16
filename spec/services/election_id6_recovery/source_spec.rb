require "rails_helper"

RSpec.describe ElectionId6Recovery::Source do
  let(:connection) do
    instance_double(
      PG::Connection,
      exec: nil,
      exec_params: [],
      transaction_status: PG::PQTRANS_IDLE,
      close: nil
    )
  end

  before do
    allow(PG).to receive(:connect).and_return(connection)
  end

  it "requires LEGACY_DATABASE_URL" do
    source = described_class.new(database_url: nil, storage_root: "/safe/storage")

    expect { source.load }
      .to raise_error(ElectionId6Recovery::SourceContractError, /LEGACY_DATABASE_URL/)
    expect(PG).not_to have_received(:connect)
  end

  it "requires LEGACY_STORAGE_ROOT" do
    source = described_class.new(database_url: "postgres://legacy", storage_root: nil)

    expect { source.load }
      .to raise_error(ElectionId6Recovery::SourceContractError, /LEGACY_STORAGE_ROOT/)
    expect(PG).not_to have_received(:connect)
  end

  it "loads every query in one repeatable-read read-only transaction" do
    described_class.new(database_url: "postgres://legacy", storage_root: "/safe/storage").load

    expect(PG).to have_received(:connect).with("postgres://legacy")
    expect(connection).to have_received(:exec)
      .with("BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")
    expect(connection).to have_received(:exec_params)
      .exactly(described_class::QUERIES.size).times
    expect(connection).to have_received(:exec).with("COMMIT")
    expect(connection).to have_received(:close)
  end

  it "limits source queries to Election ID 6 and closed final sessions" do
    described_class.new(database_url: "postgres://legacy", storage_root: "/safe/storage").load

    expect(connection).to have_received(:exec_params)
      .with(include("elections.id = $1"), [ElectionId6Recovery::ELECTION_ID])
      .at_least(:once)
    expect(connection).to have_received(:exec_params)
      .with(include("election_sessions.status = 20"), [ElectionId6Recovery::ELECTION_ID])
      .at_least(:once)
  end

  it "does not serialize source rows or write files" do
    allow(File).to receive(:write)
    allow(File).to receive(:binwrite)

    described_class.new(database_url: "postgres://legacy", storage_root: "/safe/storage").load

    expect(File).not_to have_received(:write)
    expect(File).not_to have_received(:binwrite)
  end
end
