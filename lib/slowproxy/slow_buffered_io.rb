# Extension for Net::BufferedIO
module Slowproxy
  module SlowBufferedIO
    BUFSIZE = Net::BufferedIO::BUFSIZE # 1024 * 16

    def self.bps=(bps)
      @bps = bps
      @wait = nil
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

    def self.wait
      @wait ||= 1 / ((bps / 8.0) / BUFSIZE)
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
      logger.info "wait for read (#{SlowBufferedIO.wait}s)" if logger
      SlowBufferedIO.apply_delay
      sleep SlowBufferedIO.wait
      super
      @rbuf = ''.b if SlowBufferedIO.drop?
    end

    def write0(str)
      if str.bytesize > BUFSIZE
        logger.info "wait for write (#{str.bytesize * 8.0 / SlowBufferedIO.bps}s)" if logger
        len = 0
        str.each_byte.each_slice(BUFSIZE) do |bytes|
          SlowBufferedIO.apply_delay
          if SlowBufferedIO.drop?
            len += bytes.length
          else
            len += super(bytes.pack("C*"))
          end
          sleep SlowBufferedIO.wait
        end
        len
      else
        SlowBufferedIO.apply_delay
        return str.bytesize if SlowBufferedIO.drop?
        super
      end
    end

    def logger
      SlowBufferedIO.logger
    end
  end
end

