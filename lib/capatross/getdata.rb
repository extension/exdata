# === COPYRIGHT:
# Copyright (c) North Carolina State University
# === LICENSE:
# see LICENSE file
require 'json'
require 'rest-client'
require 'mysql2'

module Capatross

  class GetData

    def known_applications
      Capatross.settings.getdata.applications.to_hash.keys.map{|appname| appname.to_s}
    end

    def drop_tables_for_database(database_name)
      dbsettings = {}
      settings.getdata.dbsettings.to_hash.each do |key,value|
        dbsettings[key.to_s] = value
      end
      dbsettings['database'] = database_name

      connection_settings = {}
      dbsettings.each do |key,value|
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

    def post_a_copy_request(appname)
      request_options = {appname: appname, data_key: Capatross.settings.capatross_key}

      begin
        result = RestClient.post("#{Capatross.settings.albatross_uri}/dumps/copy",
                                 request_options.to_json,
                                 :content_type => :json, :accept => :json)
      rescue StandardError => e
        result = e.response
      end
      JSON.parse(result)
    end

    def post_a_dump_request(appname,dbtype)
      request_options = {appname: appname, dbtype: dbtype, data_key: Capatross.settings.capatross_key}

      begin
        result = RestClient.post("#{Capatross.settings.albatross_uri}/dumps/do",
                                 request_options.to_json,
                                 :content_type => :json, :accept => :json)
      rescue StandardError => e
        result = e.response
      end
      JSON.parse(result)
    end



    def get_dumpinfo(appname,dbtype)
      request_options = {appname: appname, dbtype: dbtype, data_key: Capatross.settings.capatross_key}

      begin
        result = RestClient.post("#{Capatross.settings.albatross_uri}/dumps/dumpinfo",
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

  end

end
