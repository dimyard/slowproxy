# Extension for Net::BufferedIO
module Slowproxy
  module SlowBufferedIO
    BUFSIZE = Net::BufferedIO::BUFSIZE # 1024 * 16

    def self.bps=(bps)
      @bps = bps
    end

    def self.bps
      @bps ||= 128 * 1024
    end

    def self.logger=(logger)
      @logger = logger
    end

    def self.logger
      @logger
    end

    def self.sleep_for(bytes)
      return if bps <= 0
      sleep(bytes * 8.0 / bps)
    end

    def self.latency=(ms)
      @latency_ms = ms
    end

    def self.latency
      @latency_ms ||= 0
    end

    def self.jitter=(ms)
      @jitter_ms = ms
    end

    def self.jitter
      @jitter_ms ||= 0
    end

    def self.drop_rate=(rate)
      @drop_rate = rate
    end

    def self.drop_rate
      @drop_rate ||= 0.0
    end

    def self.apply_delay
      delay = latency + (jitter > 0 ? rand(-jitter..jitter) : 0)
      sleep(delay / 1000.0) if delay > 0
    end

    def self.drop?
      drop_rate > 0 && rand < drop_rate
    end

    def rbuf_fill
      super
      SlowBufferedIO.apply_delay
      if SlowBufferedIO.drop?
        @rbuf = ''.b
      else
        SlowBufferedIO.sleep_for(@rbuf.bytesize)
      end
    end

    def write0(str)
      SlowBufferedIO.apply_delay
      if SlowBufferedIO.drop?
        SlowBufferedIO.sleep_for(str.bytesize)
        str.bytesize
      else
        len = super
        SlowBufferedIO.sleep_for(len)
        len
      end
    end

    def logger
      SlowBufferedIO.logger
    end
  end
end

