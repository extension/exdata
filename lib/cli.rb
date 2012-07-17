# === COPYRIGHT:
# Copyright (c) 2012 North Carolina State University
# === LICENSE:
# see LICENSE file
require 'thor'
require 'yaml'
require 'json'
require 'capatross/version'
require 'capatross/options'
require 'capatross/deep_merge' unless defined?(DeepMerge)
require 'rest-client'
require 'net/scp'
require 'mathn'

module Capatross
  class CLI < Thor
    include Thor::Actions

    # these are not the tasks that you seek
    def self.source_root
      File.expand_path(File.dirname(__FILE__) + "/..")
    end
    
    no_tasks do
      
      def load_rails(environment)
        if !ENV["RAILS_ENV"] || ENV["RAILS_ENV"] == ""
          ENV["RAILS_ENV"] = environment
        end
        begin
          require "./config/environment"
        rescue LoadError
          puts 'capatross uses rails for certain features, it appears you are not at the root of a rails application, exiting...'
          exit(1)
        end
      end
          
      def logsdir
        './capatross_logs'
      end
      
      def copy_configs
        # campout.yml
        destination = "./config/capatross.yml"
        if(!File.exists?(destination))
          copy_file('templates/capatross.yml',destination)
        end
      end
            
      def add_local_to_gitignore
        gitignore_file = './.gitignore'
        if(File.exists?(gitignore_file))
          # local configuration
          if(!(File.read(gitignore_file) =~ %r{config/capatross.local.yml}))
            append_file(gitignore_file,"\n# added by capatross generate_config\n/config/capatross.local.yml\n")
          end
          
          # deploylogs
          if(!(File.read(gitignore_file) =~ %r{capatross_logs}))
            append_file(gitignore_file,"\n# added by capatross generate_config\n/capatross_logs\n")
          end
                  
        end
      end
      
      def add_capatross_to_deploy
        cap_deploy_script = './config/deploy.rb'
        if(File.exists?(cap_deploy_script))
          if(!(File.read(cap_deploy_script) =~ %r{require ['|"]capatross["|']}))
            prepend_file(cap_deploy_script,"\n# added by capatross generate_config\nrequire 'capatross'\n")
          end
        end
      end
            
      def deploy_logs(dump_log_output=true)
        deploy_logs = []
        # loop through the files
        Dir.glob(File.join(logsdir,'*.json')).sort.each do |logfile|
          logdata = JSON.parse(File.read(logfile))
          if(dump_log_output)
            logdata.delete('deploy_log')
          end
          deploy_logs << logdata
        end
        
        deploy_logs
      end
      
      def check_settings(settings_to_check)
        settings_to_check.each do |check_setting|
          if(settings.send(check_setting).nil?)
            puts "Please set #{check_setting} in your capatross.yml or capatross.local.yml"
            return false
          end
        end
        true
      end
      
      def settings
        if(@settings.nil?)
          @settings = Capatross::Options.new
          @settings.load!
        end
        
        @settings
      end
      
      def post_to_deploy_server(logdata)
        # indicate that this is coming from the cli
        logdata['from_cli'] = true
        begin
          RestClient.post("#{settings.albatross_uri}#{settings.albatross_deploy_path}",
                          logdata.to_json,
                          :content_type => :json, :accept => :json)
        rescue=> e
          e.response
        end
      end
      
      def check_post_result(response)
        if(!response.code == 200)
          return false
        else
          begin
            parsed_response = JSON.parse(response)
            if(parsed_response['success'])
              return true
            else
              return false
            end
          rescue
            return false
          end
        end
      end
        
    end


    desc "about", "about capatross"  
    def about
      puts "Capatross Version #{Capatross::VERSION}: Post logs from a capistrano deploy to the deployment server, as well as a custom deploy-tracking application."
    end
    
    desc "generate_config", "generate capatross configuration files"
    def generate_config
      copy_configs
      add_local_to_gitignore
      add_capatross_to_deploy
    end
    
    desc "list", "list local deploys"
    def list
      if(!File.exists?(logsdir))
         say("Error: Capatross log directory (#{logsdir}) not present", :red)
      end
          
      deploy_logs.sort_by{|log| log['start']}.each do |log|
        if(log['success'])
          message = "#{log['capatross_id']} : Revision: #{log['deployed_revision']} deployed at #{log['start'].to_s} to #{log['location']}"
        else
          message = "#{log['capatross_id']} : Deploy failed at #{log['start'].to_s} to #{log['location']}"
        end
        
        if(log['finish_posted'])
          message += ' (posted)'
          say(message)
        else
          message += ' (not posted)'
          say(message,:yellow)
        end
      end
    end
    
    desc "post", "post or repost the logdata from the specified local deploy"
    method_option :log, :aliases => '-l', :type => :string, :required => true, :desc => "The capatross deploy id to post/repost (use 'list' to show known deploys)"
    def post
      logfile = "./capatross_logs/#{options[:log]}.json"
      if(!File.exists?(logfile))
         say("Error: The specified capatross log (#{options[:log]}) was not found", :red)
      end
      logdata = JSON.parse(File.read(logfile))
      
      result = post_to_deploy_server(logdata)
      if(check_post_result(result))                        
        say("Log data posted to #{settings.albatross_uri}#{settings.albatross_deploy_path}")
        # update that we posted
        logdata['finish_posted'] = true
        File.open(logfile, 'w') {|f| f.write(logdata.to_json) }
      else
        say("Unable to post log data to #{settings.albatross_uri}#{settings.albatross_deploy_path} (Code: #{result.response.code })",:red)
      end
    end
    
    desc "sync", "post all unposted deploys"
    def sync
      if(!File.exists?(logsdir))
         say("Error: Capatross log directory (#{logsdir}) not present", :red)
      end
      
      deploy_logs(false).each do |log|
        if(!log['finish_posted'])
          result = post_to_deploy_server(log)
          if(check_post_result(result))
            say("#{log['capatross_id']} data posted to #{settings.albatross_uri}#{settings.albatross_deploy_path}")
            # update that we posted
            log['finish_posted'] = true
            logfile = File.join(logsdir,"#{log['capatross_id']}.json")
            File.open(logfile, 'w') {|f| f.write(log.to_json) }
          else
            say("Unable to post #{log['capatross_id']} data to #{settings.albatross_uri}#{settings.albatross_deploy_path} (Code: #{result.response.code })",:red)
          end
        end
      end
    end
    
    
    desc "getdata", "Download and replace my local database with new data"
    method_option :environment,:default => 'development', :aliases => "-e", :desc => "Rails environment"
    method_option :dbsettings,:default => 'development', :aliases => "-d", :desc => "database.yml settings"
    def getdata
      load_rails(options[:environment])
      
      # check for required settings
      exit(1) if !check_settings(['getdata_host','getdata_path','getdata_user','getdata_mysqlbin'])
      
      # download the file
      if(!settings.getdata_files.nil?)
        datafile = settings.getdata_files.send(options[:dbsettings])
        if(datafile.nil?)
          puts "No datafile specified for #{options[:dbsettings]}"
          exit(1)
        end
      elsif(!settings.getdata_file.nil?)
        datafile = settings.getdata_file
      else
        puts "Please set getdata_files['#{options[:dbsettings]}'] or getdata_file in the capatross settings"
        exit(1)
      end
        
      remotefile = "#{settings.getdata_path}/#{datafile}.gz"
      say "Downloading #{remotefile} from #{settings.getdata_host} (this might take a while)..."
      Net::SSH.start(settings.getdata_host, settings.getdata_user, :port => 24) do |ssh|
        ssh.scp.download!(remotefile,"#{Rails.root.to_s}/tmp/#{datafile}.gz") do |ch, name, sent, total|
          #downloaded = format("%.1f", (sent/total)*100)
          #puts "  Downloaded #{downloaded}% ..."          
        end
      end
      
      dbsettings = ActiveRecord::Base.configurations[options[:dbsettings]]
      gunzip_command = "gunzip --force #{Rails.root.to_s}/tmp/#{datafile}.gz"
      db_import_command = "#{settings.getdata_mysqlbin} --default-character-set=utf8 -u#{dbsettings['username']} -p#{dbsettings['password']} #{dbsettings['database']} < #{Rails.root}/tmp/#{datafile}"
      
      # gunzip
      say "Unzipping #{Rails.root.to_s}/tmp/#{datafile}.gz..."
      run(gunzip_command, :verbose => false)
      
      # dump
      say "Dumping the tables from #{dbsettings['database']}..."
      ActiveRecord::Base.connection.tables.each do |table|
        say "  dropping #{table}..."
        ActiveRecord::Base.connection.execute("DROP table #{table};")
      end
      
      # import
      say "Importing data into #{dbsettings['database']} (this might take a while)..."
      run(db_import_command, :verbose => false)
    end
    
      
      
      
    # 
    # desc "prune", "prune old deploy logs"
    # def prune
    # end
              
  end
  
end
