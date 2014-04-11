# === COPYRIGHT:
# Copyright (c) 2012 North Carolina State University
# === LICENSE:
# see LICENSE file
require 'rugged'
require 'rest-client'

require 'getdata/version'
require 'getdata/deep_merge' unless defined?(DeepMerge)
require 'getdata/options'
require 'getdata/core'

module GetData

  def self.settings
    if(@settings.nil?)
      @settings = GetData::Options.new
      @settings.load!
    end

    @settings
  end

  def self.has_getdata_key?
    !settings.getdata_key.nil?
  end


end


