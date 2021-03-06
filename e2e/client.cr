# Copyright © 2017-2018 The SushiChain Core developers
#
# See the LICENSE file at the top-level directory of this distribution
# for licensing information.
#
# Unless otherwise agreed in a custom licensing agreement with the SushiChain Core developers,
# no part of this software, including this file, may be copied, modified,
# propagated, or distributed except according to the terms contained in the
# LICENSE file.
#
# Removal or modification of this copyright notice is prohibited.

require "random"
require "./utils"

module ::E2E
  class Client < Tokoroten::Worker
    @@client : Tokoroten::Worker? = nil
    @@no_transactions : Bool = false

    alias ClientWork = NamedTuple(call: Int32, content: String)

    struct Initialize
      JSON.mapping({node_ports: Array(Int32), num_miners: Int32, num_tps: Int32})
    end

    struct Result
      JSON.mapping({num_transactions: Int32, duration: Float64})
    end

    def self.client
      @@client.not_nil!
    end

    def self.initialize(node_ports : Array(Int32), num_miners : Int32, no_transactions : Bool, num_tps : Int32)
      @@client = Client.create(1)[0]
      @@no_transactions = no_transactions

      puts "Transactions Per Second goal: #{num_tps}"
      puts "(as many as possible)" if num_tps == 0

      request = {call: 0, content: {node_ports: node_ports, num_miners: num_miners, num_tps: num_tps}.to_json}.to_json
      client.exec(request)
    end

    def self.launch
      request = {call: 1, content: ""}.to_json
      client.exec(request)
    end

    def self.finish
      request = {call: 2, content: ""}.to_json
      client.exec(request)
    end

    def task(message : String)
      work = ClientWork.from_json(message)

      case work[:call]
      when 0 # initialize
        initialize = Initialize.from_json(work[:content])

        @node_ports = initialize.node_ports
        @num_miners = initialize.num_miners
        @num_tps = initialize.num_tps
      when 1 # launch
        launch
      when 2 # finish
        kill

        response({num_transactions: num_transactions, duration: duration}.to_json)
      end
    end

    def self.receive
      client.receive
    end

    @transaction_ids = [] of String

    @alive : Bool = true

    @node_ports : Array(Int32) = [] of Int32
    @num_miners : Int32 = 0
    @num_tps : Int32 = 0

    def create_transaction(transaction_counter : Int64)
      sender = Random.rand(@num_miners)
      recipient = Random.rand(@num_miners)

      if transaction_id = create(@node_ports.sample, sender, recipient, transaction_counter)
        @launch_time ||= Time.utc
        @transaction_ids << transaction_id
      end
    end

    def launch
      if @@no_transactions
        @launch_time ||= Time.utc
        nil
      else
        spawn do
          transaction_counter = 0_i64
          while @alive
            begin
              create_transaction(transaction_counter)
              if @num_tps > 0
                sleepy_time = 1000 / @num_tps
                sleep sleepy_time.milliseconds
              end
              transaction_counter += 1_i64
            rescue e : Exception
              STDERR.puts red(e.message.not_nil!)
            end
          end
        end
      end
    end

    def kill
      @kill_time = Time.utc
      @alive = false
    end

    def num_transactions : Int32
      @transaction_ids.size
    end

    def duration : Float64
      raise "@launch_time or @kill_time is nil!" if @launch_time.nil? || @kill_time.nil?
      (@kill_time.not_nil! - @launch_time.not_nil!).total_seconds
    end

    include Utils
  end
end
