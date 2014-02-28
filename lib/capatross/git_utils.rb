# === COPYRIGHT:
# Copyright (c) 2012 North Carolina State University
# Original (c) 2012 Jason Adam Young
# === LICENSE:
# see LICENSE file
require 'rugged'

module Capatross
  class GitUtils

    def initialize(path)
      @path = path
      if(localrepo)
        return self
      else
        return nil
      end
    end

    def localrepo
      if(@localrepo.nil?)
        begin
          @localrepo = Rugged::Repository.new(@path)
        rescue Rugged::RepositoryError
        end
      end
      @localrepo
    end

    def user_name
      @user_name ||= localrepo.config['user.name']
    end

    def user_email
      @user_email ||= localrepo.config['user.email']
    end

  end
end
