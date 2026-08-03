RSpec.describe Neo4j::Driver::Internal::Cluster::ClusterRoutingTable do
  let(:database) { Neo4j::Driver::Internal::DatabaseNameUtil.default_database }
  let(:router) { Neo4j::Driver::Net::ServerAddress.of('router', 7687) }
  let(:writer) { Neo4j::Driver::Net::ServerAddress.of('writer', 7687) }
  let(:reader) { Neo4j::Driver::Net::ServerAddress.of('reader', 7687) }
  let(:routing_table) { described_class.new(database, nil, router) }

  before do
    routing_table.update(
      Neo4j::Driver::Internal::Cluster::ClusterComposition.new(
        expiration_timestamp: Time.now + 300,
        database_name: database,
        readers: [reader],
        writers: [writer],
        routers: [router]
      )
    )
  end

  describe '#forget_writer' do
    # Regression test for https://github.com/Profinda/hal/issues/2820
    # `forget_writer` used to call `@table_lock.write_lock`, which does not exist on
    # `Concurrent::ReentrantReadWriteLock` (only `with_write_lock`/`acquire_write_lock`/etc.), raising:
    #   NoMethodError: undefined method 'write_lock' for an instance of Concurrent::ReentrantReadWriteLock
    # This crashed the driver's write-failure recovery path (e.g. after a `Neo.ClientError.Cluster.NotALeader`
    # response) instead of evicting the stale writer and retrying against the real leader.
    it 'does not raise NoMethodError' do
      expect { routing_table.forget_writer(writer) }.not_to raise_error
    end

    it 'removes the address from the writers' do
      routing_table.forget_writer(writer)

      expect(routing_table.writers).not_to include(writer)
    end

    it 'marks the address as disused, keeping it visible via #servers' do
      routing_table.forget_writer(writer)

      expect(routing_table.servers).to include(writer)
    end

    it 'is safe to call for an address that is not currently a writer' do
      unknown = Neo4j::Driver::Net::ServerAddress.of('unknown', 7687)

      expect { routing_table.forget_writer(unknown) }.not_to raise_error
      expect(routing_table.servers).to include(unknown)
    end
  end
end
