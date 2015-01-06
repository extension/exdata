# === COPYRIGHT:
# Copyright (c) North Carolina State University
# === LICENSE:
# see LICENSE file
require 'json'
require 'rest-client'
require 'mysql2'
require 'open3'
require 'net/ssh'
require 'net/scp'

module GetData

  class GetDataError < StandardError; end

  class Core

    attr_reader :appname, :dbtype

    def self.known_applications
      GetData.settings.applications.to_hash.keys.map{|appname| appname.to_s}
    end

    def initialize(options)
      if(options[:appname] and self.class.known_applications.include?(options[:appname]))
        @appname = options[:appname]
      else
        raise GetDataError, "invalid application name #{appname}"
      end

      @dbtype = (options[:dbtype].nil? ? 'production' : options[:dbtype])
      @localfile = options[:localfile] if (!options[:localfile].nil? and options[:localfile] != 'default')
    end

    def run_command(command,debug = false)
      puts "running #{command}" if debug
      stdin, stdout, stderr = Open3.popen3(command)
      results = stdout.readlines + stderr.readlines
      return results.join('')
    end

    def capture_stderr &block
      real_stderr, $stderr = $stderr, StringIO.new
      yield
      $stderr.string
    ensure
      $stderr = real_stderr
    end

    def dumpinfo
      if(!@dumpinfo)
        @dumpinfo = get_dumpinfo
      end
      @dumpinfo
    end

    def last_dumped
      begin
        last_dumped_at = Time.parse(dumpinfo['last_dumped_at'])
        last_dumped_at.localtime.strftime("%Y/%m/%d %H:%M %Z")
      rescue
        'unknown'
      end
    end

    def remotefile
      # remotefile is expected to be a gzip-compressed file ending in .gz
      self.dumpinfo['file']
    end

    def localfile
      if(!@localfile)
        @localfile = "/tmp/" + File.basename(remotefile,'.gz') + "_#{self.dbtype}"
      end
      @localfile
    end

    def localfile_downloaded
      self.localfile + ".gz"
    end


    def remotehost
      GetData.settings.host
    end

    def humanize_size
      humanize_bytes(dumpinfo['size'])
    end

    def gunzip_command
     "gunzip --force #{self.localfile_downloaded}"
    end

    def db_import_command
      base_command_array = []
      base_command_array << "#{GetData.settings.mysqlbin}"
      base_command_array << "--default-character-set=utf8"
      base_command_array << "--user=#{self.dbsettings['username']}"
      base_command_array << "--password=#{self.dbsettings['password']}"
      base_command_array << "#{self.dbsettings['database']}"
      base_command = base_command_array.join(' ')
      "#{base_command} < #{self.localfile}"
    end

    def gunzip_localfile
      run_command(self.gunzip_command)
    end

    def download_remotefile(print_progress = true)
      Net::SSH.start(GetData.settings.host, GetData.settings.user, :port => 24) do |ssh|
        print "Downloaded " if print_progress
        ssh.scp.download!(remotefile,localfile_downloaded) do |ch, name, sent, total|
          print "\r" if print_progress
          print "Downloaded " if print_progress
          print "#{self.percentify(sent/total.to_f)} #{self.humanize_bytes(sent)} of #{self.humanize_bytes(total)}" if print_progress
        end
        puts " ...done!" if print_progress
      end
    end

    def database_name
      GetData.settings.applications.send(appname)
    end

    def dbsettings
      if(!@dbsettings)
        @dbsettings = {}
        GetData.settings.dbsettings.to_hash.each do |key,value|
          @dbsettings[key.to_s] = value
        end

        # bail if no database name
        if(!self.database_name)
          raise GetDataError, "invalid database name for #{appname}"
        end
        @dbsettings['database'] = self.database_name
      end
      @dbsettings
    end

    def check_for_db_connection
      connection_settings = {}
      self.dbsettings.each do |key,value|
        if(key != 'database')
          connection_settings[key.to_sym] = value
        end
      end
      begin
        client = Mysql2::Client.new(connection_settings)
        result = client.query("SHOW TABLES FROM #{dbsettings['database']}")
      rescue
        raise GetDataError, "Unable to connect to the database #{dbsettings['database']}"
      end
      return result.count
    end


    def drop_tables_for_database
      connection_settings = {}
      self.dbsettings.each do |key,value|
        if(key != 'database')
          connection_settings[key.to_sym] = value
        end
      end
      client = Mysql2::Client.new(connection_settings)
      result = client.query("SHOW TABLES FROM #{dbsettings['database']}")
      tables = []
      result.each do |table_hash|
        tables += table_hash.values
      end
      result = client.query("USE #{dbsettings['database']};")
      tables.each do |table|
        result = client.query("DROP table #{table};")
      end
    end

    def import_localfile_to_database(print_progress = true)
      if(print_progress)
        show_wait_spinner {
          run_command(self.db_import_command)
        }
        puts " done!" if print_progress
      else
        run_command(self.db_import_command)
      end
    end


    def post_a_copy_request
      request_options = {appname: self.appname, data_key: GetData.settings.getdata_key}

      begin
        result = RestClient.post("#{GetData.settings.albatross_uri}/dumps/copy",
                                 request_options.to_json,
                                 :content_type => :json, :accept => :json)
      rescue StandardError => e
        result = e.response
      end
      JSON.parse(result)
    end

    def post_a_dump_request
      request_options = {appname: self.appname, dbtype: self.dbtype, data_key: GetData.settings.getdata_key}

      begin
        result = RestClient.post("#{GetData.settings.albatross_uri}/dumps/do",
                                 request_options.to_json,
                                 :content_type => :json, :accept => :json)
      rescue StandardError => e
        result = e.response
      end
      JSON.parse(result)
    end



    def get_dumpinfo
      request_options = {appname: self.appname, dbtype: self.dbtype, data_key: GetData.settings.getdata_key}

      begin
        result = RestClient.post("#{GetData.settings.albatross_uri}/dumps/dumpinfo",
                         request_options.to_json,
                         :content_type => :json, :accept => :json)
      rescue StandardError => e
        result = e.response
      end
      JSON.parse(result)
    end

    # code from: https://github.com/ripienaar/mysql-dump-split
    def humanize_bytes(bytes)
      if(bytes != 0)
        units = %w{B KB MB GB TB}
        e = (Math.log(bytes)/Math.log(1024)).floor
        s = "%.1f"%(bytes.to_f/1024**e)
        s.sub(/\.?0*$/,units[e])
      end
    end

    def percentify(number)
      s = "%.0f\%"%(number*100)
    end

    # from:
    # http://stackoverflow.com/questions/10262235/printing-an-ascii-spinning-cursor-in-the-console
    def show_wait_spinner(fps=10)
      chars = %w[| / - \\]
      delay = 1.0/fps
      iter = 0
      spinner = Thread.new do
        while iter do  # Keep spinning until told otherwise
          print chars[(iter+=1) % chars.length]
          sleep delay
          print "\b"
        end
      end
      yield.tap{       # After yielding to the block, save the return value
        iter = false   # Tell the thread to exit, cleaning up after itself…
        spinner.join   # …and wait for it to do so.
      }                # Use the block's return value as the method's
    end

  end

end
