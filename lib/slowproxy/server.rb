require 'webrick/httpproxy'

module Slowproxy
  class Server < WEBrick::HTTPProxyServer
    def initialize(config, default = WEBrick::Config::HTTP)
      @bps = config.delete(:BPS)
      @latency = config.delete(:Latency) || 0
      @jitter = config.delete(:Jitter) || 0
      @drop_rate = config.delete(:DropRate) || 0.0
      SlowBufferedIO.bps = @bps if @bps
      SlowBufferedIO.latency = @latency
      SlowBufferedIO.jitter = @jitter
      SlowBufferedIO.drop_rate = @drop_rate
      super
      logger.info "#{number_to_human_size(@bps)}bps"
      SlowBufferedIO.logger = logger
    end

    def number_to_human_size(n)
      suffixes = ["", "K", "M", "G"]
      suffixes.each_with_index.to_a.reverse.each do |suffix, index|
        one = 1024 ** index
        return "#{n / one} #{suffix}" if n >= one
      end
    end

    def perform_proxy_request(req, res)
      uri = req.request_uri
      path = uri.path.dup
      path << "?" << uri.query if uri.query
      header = setup_proxy_header(req, res)
      upstream = setup_upstream_proxy_authentication(req, res, header)
      response = nil

      http = Net::HTTP.new(uri.host, uri.port, upstream.host, upstream.port)
      http.start do
        ########## prepend Net::SlowBufferedIO
        http.instance_eval do
          class << @socket
            prepend Slowproxy::SlowBufferedIO
          end
        end
        ########## /prepend Net::SlowBufferedIO
        if @config[:ProxyTimeout]
          ##################################   these issues are
          http.open_timeout = 30   # secs  #   necessary (maybe because
          http.read_timeout = 60   # secs  #   Ruby's bug, but why?)
          ##################################
        end
        response = yield(http, path, header)
      end

      # Persistent connection requirements are mysterious for me.
      # So I will close the connection in every response.
      res['proxy-connection'] = "close"
      res['connection'] = "close"

      # Convert Net::HTTP::HTTPResponse to WEBrick::HTTPResponse
      res.status = response.code.to_i
      choose_header(response, res)
      set_cookie(response, res)
      set_via(res)
      res.body = response.body
    end

    def do_CONNECT(req, res)
      # Proxy Authentication
      proxy_auth(req, res)

      ua = Thread.current[:WEBrickSocket]  # User-Agent
      raise WEBrick::HTTPStatus::InternalServerError,
        "[BUG] cannot get socket" unless ua

      host, port = req.unparsed_uri.split(":", 2)
      # Proxy authentication for upstream proxy server
      if proxy = proxy_uri(req, res)
        proxy_request_line = "CONNECT #{host}:#{port} HTTP/1.0"
        if proxy.userinfo
          credentials = "Basic " + [proxy.userinfo].pack("m").delete("\n")
        end
        host, port = proxy.host, proxy.port
      end

      begin
        @logger.debug("CONNECT: upstream proxy is `#{host}:#{port}'.")
        os = TCPSocket.new(host, port)     # origin server

        if proxy
          @logger.debug("CONNECT: sending a Request-Line")
          os << proxy_request_line << CRLF
          @logger.debug("CONNECT: > #{proxy_request_line}")
          if credentials
            @logger.debug("CONNECT: sending a credentials")
            os << "Proxy-Authorization: " << credentials << CRLF
          end
          os << CRLF
          proxy_status_line = os.gets(LF)
          @logger.debug("CONNECT: read a Status-Line form the upstream server")
          @logger.debug("CONNECT: < #{proxy_status_line}")
          if %r{^HTTP/\d+\.\d+\s+200\s*} =~ proxy_status_line
            while line = os.gets(LF)
              break if /\A(#{CRLF}|#{LF})\z/om =~ line
            end
          else
            raise WEBrick::HTTPStatus::BadGateway
          end
        end
        @logger.debug("CONNECT #{host}:#{port}: succeeded")
        res.status = WEBrick::HTTPStatus::RC_OK
      rescue => ex
        @logger.debug("CONNECT #{host}:#{port}: failed `#{ex.message}'")
        res.set_error(ex)
        raise WEBrick::HTTPStatus::EOFError
      ensure
        if handler = @config[:ProxyContentHandler]
          handler.call(req, res)
        end
        res.send_response(ua)
        access_log(@config, req, res)

        # Should clear request-line not to send the response twice.
        # see: HTTPServer#run
        req.parse(NullReader) rescue nil
      end

      client_bytes = 0
      server_bytes = 0
      handshake_bytes = 1024
      begin
        while fds = IO.select([ua, os])
          if fds[0].include?(ua)
            buf = ua.sysread(SlowBufferedIO::BUFSIZE)
            @logger.debug("CONNECT: #{buf.bytesize} byte from User-Agent")
            SlowBufferedIO.apply_delay
            drop = client_bytes >= handshake_bytes && SlowBufferedIO.drop?
            client_bytes += buf.bytesize
            os.syswrite(buf) unless drop
            SlowBufferedIO.sleep_for(buf.bytesize)
          elsif fds[0].include?(os)
            buf = os.sysread(SlowBufferedIO::BUFSIZE)
            @logger.debug("CONNECT: #{buf.bytesize} byte from #{host}:#{port}")
            SlowBufferedIO.apply_delay
            drop = server_bytes >= handshake_bytes && SlowBufferedIO.drop?
            server_bytes += buf.bytesize
            ua.syswrite(buf) unless drop
            SlowBufferedIO.sleep_for(buf.bytesize)
          end
        end
      rescue => ex
        os.close
        @logger.debug("CONNECT #{host}:#{port}: closed")
      end

      raise WEBrick::HTTPStatus::EOFError
    end
  end
end
