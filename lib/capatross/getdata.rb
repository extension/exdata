# === COPYRIGHT:
# Copyright (c) North Carolina State University
# === LICENSE:
# see LICENSE file
require 'json'
require 'rest-client'

module Capatross

  class GetData

    def known_applications
      Capatross.settings.getdata.applications.to_hash.keys.map{|appname| appname.to_s}
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

  end

end
