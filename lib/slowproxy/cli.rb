require "optparse"
module Slowproxy
  class CLI
    def self.start(argv)
      new.run(argv)
    end

    def run(argv)
      options = {
        port: 8989,
        bps: 128 * 1024,
        debug: false,
        latency: 0,
        jitter: 0,
        drop_rate: 0.0,
      }

      OptionParser.new do |o|
        o.banner = "Usage: #{$0} [options] [speed(g|m|k)[bps]]"
        o.on("-p PORT", "--port=PORT", Integer){|i| options[:port] = i }
        o.on("--debug", TrueClass){|b| options[:debug] = b }
        o.on("--latency N", Integer, "Fixed latency in milliseconds"){|i| options[:latency] = i }
        o.on("--jitter M", Integer, "Jitter ±M milliseconds"){|i| options[:jitter] = i }
        o.on("--drop-rate R", Float, "Drop rate between 0.0 and 1.0"){|f| options[:drop_rate] = f }
        o.parse!(argv)
        options[:bps] = parse_bps(argv.first) unless argv.empty?
      end

      logger = WEBrick::Log::new(STDOUT, options[:debug] ? WEBrick::Log::DEBUG : WEBrick::Log::INFO)

      server = Server.new(
        Logger: logger,
        Port: options[:port],
        BPS: options[:bps],
        Latency: options[:latency],
        Jitter: options[:jitter],
        DropRate: options[:drop_rate],
      )

      Signal.trap('INT') do
        server.shutdown
      end

      server.start
    end

    def parse_bps(str)
      return unless str
      case str.strip.downcase
      when /\A(\d+)(g|m|k|)(bps)?\z/
        num, order, * = $~.captures
        num.to_i * case order
        when ""
          1
        when "k"
          1024
        when "m"
          1024 ** 2
        when "g"
          1024 ** 3
        end
      end
    end
  end
end
