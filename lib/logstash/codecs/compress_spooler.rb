# encoding: utf-8
require "logstash/codecs/base"
require "logstash/timestamp"

class LogStash::Codecs::CompressSpooler < LogStash::Codecs::Base
  config_name 'compress_spooler'
  config :spool_size, :validate => :number, :default => 50
  config :compress_level, :validate => :number, :default => 6

  public
  def register
    require "msgpack"
    require "zlib"
    @buffer = []
  end

  public
  def decode(data)
    z = Zlib::Inflate.new
    data = MessagePack.unpack(z.inflate(data))
    z.finish
    z.close
    data.each do |event|
      event = LogStash::Event.new(event)

      # Coerce timestamp back into a Logstash::Timestamp
      if event["@timestamp_f"].is_a? Float
        event["@timestamp"] = LogStash::Timestamp.coerce(Time.at(event["@timestamp_f"]))
        event.remove("@timestamp_f")
      end

      yield event
    end
  end # def decode

  public
  def encode(data)
    # Scrub timestamp (doesn't serialise very well)
    data["@timestamp_f"] = data["@timestamp"].to_f
    data.remove("@timestamp")

    if @buffer.length >= @spool_size
      z = Zlib::Deflate.new(@compress_level)
      @on_event.call data, z.deflate(MessagePack.pack(@buffer), Zlib::FINISH)
      z.close
      @buffer.clear
    else
      data["@timestamp"] = data["@timestamp"].to_f
      @buffer << data.to_hash
    end
  end # def encode

  public
  def teardown
    if !@buffer.nil? and @buffer.length > 0
      @on_event.call LogStash::Event.new, @buffer
    end
    @buffer.clear
  end
end # class LogStash::Codecs::CompressSpooler
