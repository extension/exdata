# === COPYRIGHT:
# Copyright (c) 2012 North Carolina State University
# === LICENSE:
# see LICENSE file
require 'thor'
require 'getdata'
require 'highline'

module GetData
  class CLI < Thor
    include Thor::Actions

    # these are not the tasks that you seek
    def self.source_root
      File.expand_path(File.dirname(__FILE__) + "/..")
    end

    no_tasks do

      def getdata_key_check
        if(!GetData.has_getdata_key?)
          puts "Please go to https://engineering.extension.org to obtain your getdata key and run 'getdata setup'"
          exit(1)
        end
      end

      def ask_password(message)
        HighLine.new.ask(message) do |q|
          q.echo = '*'
        end
      end

      def check_database_name_for(appname)
        if(GetData.settings.dbsettings.nil?)
          puts "Please set dbsettings in your getdata settings"
          exit(1)
        end

        if(GetData.settings.applications.nil?)
          puts "Please set applications['#{appname}'] in your getdata settings"
          exit(1)
        end

        dbname = GetData.settings.applications.send(appname)
        if(dbname.nil?)
          puts "No databased specified in your getdata settings for #{appname}"
          exit(1)
        end

        dbname
      end

    end

    desc "setup", "Setup getdata on this host"
    method_option :force, :aliases => '-f', :type => :boolean, :default => false, :desc => "Force an overwrite of any existing getdata settings"
    def setup
      # check for a ~/.capatross.yml and write a toml file from those settings
      if (File.exists?(File.expand_path("~/.capatross.yml")) and !File.exists?(File.expand_path("~/exdata.toml")))
        puts "Found " + File.expand_path("~/.capatross.yml") + " - converting to " + File.expand_path("~/exdata.toml")
        require 'getdata/migrate_options'
        migrate_settings = GetData::MigrateOptions.new
        migrate_settings.load!
        @migrate_hash = migrate_settings.getdata.to_hash
        # change data_key to getdata_key
        if(@migrate_hash[:data_key])
          @migrate_hash[:getdata_key] = @migrate_hash[:data_key]
          @migrate_hash.delete(:data_key)
        end
        toml_string = TOML::Generator.new(@migrate_hash).body
        migrate_file = File.expand_path("~/exdata.toml")
        File.open(migrate_file, 'w') {|f| f.write(toml_string) }
        puts "Converted old configuration settings. You can now remove " + File.expand_path("~/.capatross.yml")
        exit(0)
      elsif(File.exists?(File.expand_path("~/exdata.toml")) and !options[:force])
        puts "Your getdata configuration file (" + File.expand_path("~/exdata.toml") + ") already exists, use --force to overwrite"
        exit(1)
      else
        config = {}
        config[:getdata_key] = ask_password('Registration key: ')
        toml_string = TOML::Generator.new(config).body
        migrate_file = File.expand_path("~/exdata.toml")
        File.open(migrate_file, 'w') {|f| f.write(toml_string) }
        puts "Wrote configuration key to " + File.expand_path("~/exdata.toml")
      end
      # todo check key?
    end


    desc "about", "about getdata"
    def about
      puts "eXData Version #{GetData::VERSION}: Utility to download data snapshots and import them locally for development"
    end

    desc "fetch", "Download data snapshots from the server for the specified application"
    method_option :appname, :default => 'prompt', :aliases => ["-a","--application"], :desc => "Application name"
    method_option :dbtype,:default => 'production', :aliases => "-t", :desc => "Database type you want information about"
    method_option :localfile,:default => 'default', :aliases => "-f", :desc => "Full path and name of the file you want to download to (defaults to a file in /tmp)"
    def fetch
      getdata_key_check
      application_list = GetData::Core.known_applications
      appname = options[:appname].downcase

      # get the file details
      if(appname == 'prompt')
        appname = ask("What application?", limited_to: application_list)
      elsif(!application_list.include?(appname))
        say("#{appname} is not a configured application. Configured applications are: #{application_list.join(', ')}")
        appname = ask("What application?", limited_to: application_list)
      end

      # will exit if settings don't exist
      check_database_name_for(appname)
      getdata = GetData::Core.new({appname: appname, dbtype: options[:dbtype], localfile: options[:localfile]})

      # error handling
      if(!getdata.dumpinfo['success'])
        puts "Unable to get database dump information for #{appname}. Reason #{getdata.dumpinfo['message'] || 'unknown'}"
        exit(1)
      end

      if(!getdata.remotefile)
        puts "Missing file in dump information for #{appname}."
        exit(1)
      end

      say "Data dump for #{appname} Size: #{getdata.humanize_size} Last dumped at: #{getdata.last_dumped}"
      say "Starting download of #{getdata.remotefile} from #{getdata.remotehost} and saving to #{getdata.localfile_downloaded}..."
      getdata.download_remotefile # outputs progress
    end

    desc "pull", "Downloads and imports a data snapshot for the specified application"
    method_option :appname, :default => 'prompt', :aliases => ["-a","--application"], :desc => "Application name"
    method_option :dbtype,:default => 'production', :aliases => "-t", :desc => "Database type you want information about"
    method_option :localfile,:default => 'default', :aliases => "-f", :desc => "Full path and name of the file you want to download to (defaults to a file in /tmp)"
    def pull
      getdata_key_check
      application_list = GetData::Core.known_applications
      appname = options[:appname].downcase

      # get the file details
      if(appname == 'prompt')
        appname = ask("What application?", limited_to: application_list)
      elsif(!application_list.include?(appname))
        say("#{appname} is not a configured application. Configured applications are: #{application_list.join(', ')}")
        appname = ask("What application?", limited_to: application_list)
      end

      # will exit if settings don't exist
      getdata = GetData::Core.new({appname: appname, dbtype: options[:dbtype], localfile: options[:localfile]})


      # error handling
      if(!getdata.dumpinfo['success'])
        puts "Unable to get database dump information for #{appname}. Reason #{getdata.dumpinfo['message'] || 'unknown'}"
        exit(1)
      end

      if(!getdata.remotefile)
        puts "Missing file in dump information for #{appname}."
        exit(1)
      end

      say "Data dump for #{appname} Size: #{getdata.humanize_size} Last dumped at: #{getdata.last_dumped}"
      say "Starting download of #{getdata.remotefile} from #{getdata.remotehost}..."
      getdata.download_remotefile # outputs progress


      # gunzip
      say "Decompressing #{getdata.localfile_downloaded}..."
      getdata.gunzip_localfile

      # drop the tables
      say "Dropping the database tables for #{getdata.database_name}"
      getdata.drop_tables_for_database

      # import
      say "Importing data into #{getdata.database_name} (this might take a while)... "
      getdata.import_localfile_to_database

    end

    desc "import", "Imports a data snapshot for the specified application if the file exists"
    method_option :appname, :default => 'prompt', :aliases => ["-a","--application"], :desc => "Application name"
    method_option :dbtype,:default => 'production', :aliases => "-t", :desc => "Database type you want information about"
    method_option :localfile,:default => 'default', :aliases => "-f", :desc => "Full path and name of the file you want to download to (defaults to a file in /tmp)"
    def import
      getdata_key_check
      application_list = GetData::Core.known_applications
      appname = options[:appname].downcase

      # get the file details
      if(appname == 'prompt')
        appname = ask("What application?", limited_to: application_list)
      elsif(!application_list.include?(appname))
        say("#{appname} is not a configured application. Configured applications are: #{application_list.join(', ')}")
        appname = ask("What application?", limited_to: application_list)
      end

      # will exit if settings don't exist
      check_database_name_for(appname)
      getdata = GetData::Core.new({appname: appname, dbtype: options[:dbtype], localfile: options[:localfile]})

      if(File.exists?(getdata.localfile_downloaded))
        # gunzip
        say "Decompressing #{getdata.localfile_downloaded}..."
        getdata.gunzip_localfile
      end

      if(!File.exists?(getdata.localfile))
        say "The specified data import file: #{getdata.localfile} does not exist. Run getdata getdata or getdata downloaddata to download the file"
        exit(1)
      end

      # drop the tables
      say "Dropping the database tables for #{getdata.database_name}"
      getdata.drop_tables_for_database

      # import
      say "Importing data into #{getdata.database_name} (this might take a while)... "
      getdata.import_localfile_to_database
    end


    desc "showsettings", "Show settings"
    def showsettings
      require 'pp'
      pp GetData.settings.to_hash
    end


    desc "dumpinfo", "Get information about a database dump for an application"
    method_option :appname, :default => 'prompt', :aliases => ["-a","--application"], :desc => "Application name"
    method_option :dbtype,:default => 'production', :aliases => "-t", :desc => "Database type you want information about"
    def info
      getdata_key_check
      application_list = GetData::Core.known_applications
      appname = options[:appname].downcase

      # get the file details
      if(appname == 'prompt')
        appname = ask("What application?", limited_to: application_list)
      elsif(!application_list.include?(appname))
        say("#{appname} is not a configured application. Configured applications are: #{application_list.join(', ')}")
        appname = ask("What application?", limited_to: application_list)
      end

      getdata = GetData::Core.new({appname: appname, dbtype: options[:dbtype]})


      # error handling
      if(!getdata.dumpinfo['success'])
        puts "Unable to get database dump information for #{appname}. Reason #{getdata.dumpinfo['message'] || 'unknown'}"
        exit(1)
      end

      if(!getdata.remotefile)
        puts "Missing file in dump information for #{appname}."
        exit(1)
      end

      require 'pp'
      pp getdata.dumpinfo.to_hash

    end


    desc "dump", "Request a database dump"
    method_option :appname, :default => 'prompt', :aliases => ["-a","--application"], :desc => "Application name"
    method_option :dbtype,:default => 'production', :aliases => "-t", :desc => "Database type you want to dump"
    def dump
      getdata_key_check
      application_list = GetData::Core.known_applications
      appname = options[:appname].downcase

      # get the file details
      if(appname == 'prompt')
        appname = ask("What application?", limited_to: application_list)
      elsif(!application_list.include?(appname))
        say("#{appname} is not a configured application. Configured applications are: #{application_list.join(', ')}")
        appname = ask("What application?", limited_to: application_list)
      end

      getdata = GetData::Core.new({appname: appname, dbtype: options[:dbtype]})
      result = getdata.post_a_dump_request

      if(!result['success'])
        puts "Unable to request a #{options[:dbtype]} database dump for #{application}. Reason #{result['message'] || 'unknown'}"
      else
        puts "#{result['message'] || 'Unknown result'}"
      end
    end

    desc "devcopy", "Request a database copy from production to development"
    method_option :appname, :default => 'prompt', :aliases => ["-a","--application"], :desc => "Application name"
    def devcopy
      getdata_key_check
      application_list = GetData::Core.known_applications
      appname = options[:appname].downcase

      # get the file details
      if(appname == 'prompt')
        appname = ask("What application?", limited_to: application_list)
      elsif(!application_list.include?(appname))
        say("#{appname} is not a configured application. Configured applications are: #{application_list.join(', ')}")
        appname = ask("What application?", limited_to: application_list)
      end

      getdata = GetData::Core.new({appname: appname, dbtype: options[:dbtype]})
      
      result = getdata.post_a_copy_request

      if(!result['success'])
        puts "Unable to request a database copy for #{appname}. Reason #{result['message'] || 'unknown'}"
      else
        puts "#{result['message'] || 'Unknown result'}"
      end
    end

  end

end
