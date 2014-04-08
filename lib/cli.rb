# === COPYRIGHT:
# Copyright (c) 2012 North Carolina State University
# === LICENSE:
# see LICENSE file
require 'thor'
require 'capatross'
require 'highline'

module Capatross
  class CLI < Thor
    include Thor::Actions

    # these are not the tasks that you seek
    def self.source_root
      File.expand_path(File.dirname(__FILE__) + "/..")
    end

    no_tasks do

      def capatross_key_check
        if(!Capatross.has_capatross_key?)
          puts "Please go to https://engineering.extension.org to obtain your capatross key and run 'capatross setup'"
          exit(1)
        end
      end

      def ask_password(message)
        HighLine.new.ask(message) do |q|
          q.echo = '*'
        end
      end

      def get_database_name_for(application)
        if(settings.getdata.dbsettings.nil?)
          puts "Please set getdata.dbsettings in your capatross settings"
          exit(1)
        end

        if(settings.getdata.applications.nil?)
          puts "Please set getdata.applications['#{application}'] in your capatross settings"
          exit(1)
        end

        dbname = settings.getdata.applications.send(application)
        if(dbname.nil?)
          puts "No databased specified in your capatross settings for #{application}"
          exit(1)
        end

        dbname
      end




      def drop_tables_mysql2(dbsettings)
        say "Dumping the tables from #{dbsettings['database']}... "

        say "done!"
      end

      def logsdir
        './capatross_logs'
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

      def settings
        Capatross.settings
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

    desc "setup", "Setup capatross on this host"
    method_option :force, :aliases => '-f', :type => :boolean, :default => false, :desc => "Force an overwrite of any existing capatross settings"
    def setup
      # check for a ~/.capatross.yml and write a toml file from those settings
      if (File.exists?(File.expand_path("~/.capatross.yml")) and !File.exists?(File.expand_path("~/capatross.toml")))
        puts "Found " + File.expand_path("~/.capatross.yml") + " - converting to " + File.expand_path("~/capatross.toml")
        require 'capatross/migrate_options'
        migrate_settings = Capatross::MigrateOptions.new
        migrate_settings.load!
        @migrate_hash = migrate_settings.to_hash
        # change data_key to capatross_key
        if(@migrate_hash[:getdata][:data_key])
          @migrate_hash[:capatross_key] = @migrate_hash[:getdata][:data_key]
          @migrate_hash[:getdata].delete(:data_key)
        end
        toml_string = TOML::Generator.new(@migrate_hash).body
        migrate_file = File.expand_path("~/capatross.toml")
        File.open(migrate_file, 'w') {|f| f.write(toml_string) }
        puts "Converted old configuration settings. You can now remove " + File.expand_path("~/.capatross.yml")
        exit(0)
      elsif(File.exists?(File.expand_path("~/capatross.toml")) and !options[:force])
        puts "Your capatross configuration file (" + File.expand_path("~/capatross.toml") + ") already exists, use --force to overwrite"
        exit(1)
      else
        config = {}
        config[:capatross_key] = ask_password('Registration key: ')
        toml_string = TOML::Generator.new(config).body
        migrate_file = File.expand_path("~/capatross.toml")
        File.open(migrate_file, 'w') {|f| f.write(toml_string) }
        puts "Wrote configuration key to " + File.expand_path("~/capatross.toml")
      end
      # todo check key?
    end


    desc "about", "about capatross"
    def about
      puts "Capatross Version #{Capatross::VERSION}: Post logs from a capistrano deploy to the deployment server, as well as a custom deploy-tracking application."
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
    method_option :appname, :default => 'prompt', :aliases => "-a", :desc => "Application name"
    method_option :dbtype,:default => 'production', :aliases => "-t", :desc => "Database type you want information about"
    def getdata
      capatross_key_check
      getdata = Capatross::GetData.new
      application_list = getdata.known_applications
      appname = options[:appname].downcase

      # get the file details
      if(appname == 'prompt')
        appname = ask("What application?", limited_to: application_list)
      elsif(!application_list.includes?(application))
        say("#{application} is not a configured application. Configured applications are: #{application_list.join(', ')}")
        appname = ask("What application?", limited_to: application_list)
      end

      # will exit if settings don't exist
      database_name = get_database_name_for(appname)


      # get the file details
      result = getdata.get_dumpinfo(appname,options[:dbtype])

      if(!result['success'])
        puts "Unable to get database dump information for #{appname}. Reason #{result['message'] || 'unknown'}"
        exit(1)
      end

      if(!result['file'])
        puts "Missing file in dump information for #{appname}."
        exit(1)
      end

      begin
        last_dumped_at = Time.parse(result['last_dumped_at'])
        last_dumped_string = last_dumped_at.localtime.strftime("%Y/%m/%d %H:%M %Z")
      rescue
        last_dumped_string = 'unknown'
      end


      remotefile = result['file']
      local_compressed_file = File.basename(remotefile)
      local_file = File.basename(local_compressed_file,'.gz')

      say "Data dump for #{application} Size: #{getdata.humanize_bytes(result['size'])} Last dumped at: #{last_dumped_string}"
      say "Starting download of #{remotefile} from #{settings.getdata.host}..."
      Net::SSH.start(settings.getdata.host, settings.getdata.user, :port => 24) do |ssh|
        print "Downloaded "
        ssh.scp.download!(remotefile,"/tmp/#{local_compressed_file}") do |ch, name, sent, total|
          print "\r"
          print "Downloaded "
          print "#{percentify(sent/total)} #{humanize_bytes(sent)} of #{humanize_bytes(total)}"
        end
        puts " ...done!"
      end

      gunzip_command = "gunzip --force /tmp/#{local_compressed_file}"
      pv_command = '/usr/local/bin/pv'
      db_import_command = "#{settings.getdata.mysqlbin} --default-character-set=utf8 -u#{dbsettings['username']} -p#{dbsettings['password']} #{dbsettings['database']} < /tmp/#{local_file}"

      # gunzip
      say "Unzipping /tmp/#{local_compressed_file}..."
      run(gunzip_command, :verbose => false)

      # dump
      getdata.drop_tables_for_database(database_name)

      # import
      say "Importing data into #{dbsettings['database']} (this might take a while)... "
      show_wait_spinner {
        run(db_import_command, :verbose => false)
      }
      puts " done!"
    end

    desc "showsettings", "Show settings"
    def showsettings
      require 'pp'
      pp Capatross.settings.to_hash
    end


    desc "dumpinfo", "Get information about a database dump for an application"
    method_option :appname, :default => 'prompt', :aliases => "-a", :desc => "Application name"
    method_option :dbtype,:default => 'production', :aliases => "-t", :desc => "Database type you want information about"
    def dumpinfo
      capatross_key_check
      getdata = Capatross::GetData.new
      application_list = getdata.known_applications
      appname = options[:appname].downcase

      # get the file details
      if(appname == 'prompt')
        appname = ask("What application?", limited_to: application_list)
      elsif(!application_list.includes?(application))
        say("#{application} is not a configured application. Configured applications are: #{application_list.join(', ')}")
        appname = ask("What application?", limited_to: application_list)
      end

      result = getdata.get_dumpinfo(appname,options[:dbtype])

      if(!result['success'])
        puts "Unable to get database dump information for #{appname}."
        puts "Reason: #{result['message'] || 'unknown'}"
        exit(1)
      end

      if(!result['file'])
        puts "Missing file in dump information for #{appname}."
        exit(1)
      end

      begin
        last_dumped_at = Time.parse(result['last_dumped_at'])
        last_dumped_string = last_dumped_at.strftime("%A, %B %e, %Y, %l:%M %p %Z")
      rescue
        last_dumped_string = 'unknown'
      end

      pp result.to_hash

    end


    desc "dodump", "Request a database dump"
    method_option :appname, :default => 'prompt', :aliases => "-a", :desc => "Application name"
    method_option :dbtype,:default => 'production', :aliases => "-t", :desc => "Database type you want to dump"
    def dodump
      capatross_key_check
      getdata = Capatross::GetData.new
      application_list = getdata.known_applications
      appname = options[:appname].downcase

      # get the file details
      if(appname == 'prompt')
        appname = ask("What application?", limited_to: application_list)
      elsif(!application_list.includes?(application))
        say("#{application} is not a configured application. Configured applications are: #{application_list.join(', ')}")
        appname = ask("What application?", limited_to: application_list)
      end

      result = getdata.post_a_dump_request(appname,options[:dbtype])

      if(!result['success'])
        puts "Unable to request a #{options[:dbtype]} database dump for #{application}. Reason #{result['message'] || 'unknown'}"
      else
        puts "#{result['message'] || 'Unknown result'}"
      end
    end

    desc "docopy", "Request a database copy from production to development"
    method_option :appname, :default => 'prompt', :aliases => "-a", :desc => "Application name"
    def docopy
      capatross_key_check
      getdata = Capatross::GetData.new
      application_list = getdata.known_applications
      appname = options[:appname].downcase

      # get the file details
      if(appname == 'prompt')
        appname = ask("What application?", limited_to: application_list)
      elsif(!application_list.includes?(application))
        say("#{application} is not a configured application. Configured applications are: #{application_list.join(', ')}")
        appname = ask("What application?", limited_to: application_list)
      end

      result = getdata.post_a_copy_request(appname)

      if(!result['success'])
        puts "Unable to request a database copy for #{appname}. Reason #{result['message'] || 'unknown'}"
      else
        puts "#{result['message'] || 'Unknown result'}"
      end
    end





    # desc "prune", "prune old deploy logs"
    # def prune
    # TODO
    # end

  end

end
