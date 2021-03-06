#
# ServerEngine
#
# Copyright (C) 2012-2013 Sadayuki Furuhashi
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.
#
module ServerEngine
  module SocketManager

    require 'socket'
    require 'ipaddr'

    class Client
      def initialize(path)
        @path = path
      end

      def listen_tcp(bind, port)
        peer = connect_peer(@path)
        begin
          SocketManager.send_peer(peer, [Process.pid, :listen_tcp, bind, port])
          res = SocketManager.recv_peer(peer)
          if res.is_a?(Exception)
            raise res
          else
            return recv_tcp(peer, res)
          end
        ensure
          peer.close
        end
      end

      def listen_udp(bind, port)
        peer = connect_peer(@path)
        begin
          SocketManager.send_peer(peer, [Process.pid, :listen_udp, bind, port])
          res = SocketManager.recv_peer(peer)
          if res.is_a?(Exception)
            raise res
          else
            return recv_udp(peer, res)
          end
        ensure
          peer.close
        end
      end
    end

    class Server
      def self.open(path)
        new(path)
      end

      def initialize(path)
        @tcp_sockets = {}
        @udp_sockets = {}
        @mutex = Mutex.new
        @path = start_server(path)
      end

      attr_reader :path

      def new_client
        Client.new(@path)
      end

      def close
        stop_server
        nil
      end

      private

      def listen_tcp(bind, port)
        key, bind_ip = resolve_bind_key(bind, port)

        @mutex.synchronize do
          if @tcp_sockets.has_key?(key)
            return @tcp_sockets[key]
          else
            return @tcp_sockets[key] = listen_tcp_new(bind_ip, port)
          end
        end
      end

      def listen_udp(bind, port)
        key, bind_ip = resolve_bind_key(bind, port)

        @mutex.synchronize do
          if @udp_sockets.has_key?(key)
            return @udp_sockets[key]
          else
            return @udp_sockets[key] = listen_udp_new(bind_ip, port)
          end
        end
      end

      def resolve_bind_key(bind, port)
        bind_ip = IPAddr.new(IPSocket.getaddress(bind))
        if bind_ip.ipv6?
          return "[#{bind_ip}]:#{port}", bind_ip
        else
          # assuming ipv4
          return "#{bind_ip}:#{port}", bind_ip
        end
      end

      def process_peer(peer)
        while true
          pid, method, bind, port = *SocketManager.recv_peer(peer)
          begin
            send_socket(peer, pid, method, bind, port)
          rescue => e
            SocketManager.send_peer(peer, e)
          end
        end
      ensure
        peer.close
      end
    end

    def self.send_peer(peer, obj)
      data = Marshal.dump(obj)
      peer.write [data.bytesize].pack('N')
      peer.write data
    end

    def self.recv_peer(peer)
      len = peer.read(4).unpack('N').first
      data = peer.read(len)
      Marshal.load(data)
    end

    require_relative 'utils'

    if ServerEngine.windows?
      require_relative 'socket_manager_win'
      Client.include(SocketManagerWin::ClientModule)
      Server.include(SocketManagerWin::ServerModule)
    else
      require_relative 'socket_manager_unix'
      Client.include(SocketManagerUnix::ClientModule)
      Server.include(SocketManagerUnix::ServerModule)
    end

  end
end
