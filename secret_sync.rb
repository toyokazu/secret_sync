require 'yaml'
require 'optparse'
require 'logger'

class SecretSync
  OPERATIONS = %w(backup restore)

  # Parsed options
  attr_accessor :options
  attr_accessor :config
  attr_accessor :logger

  def self.rsync
    "/usr/bin/env rsync"
  end

  def self.skip_item?(item)
    (File.basename(item) != '.' && File.basename(item) != '..')
  end

  def initialize(argv, options = {})
    @argv = argv

    # Default options values
    @options = options

    parse!

    @logger = Logger.new(STDOUT)
    @logger.level = Logger::INFO

    @config = YAML.load_file(@options[:config] || 'sync.yml')
    @firefox_profile_path = firefox_profile_path
  end

  def parser
    @parser ||= OptionParser.new do |opts|
      opts.banner = "Usage: #{self.class.command} [options]"       
      opts.separator ""
      opts.separator "options:"
      opts.on("-c", "--config=file", String, "Use custom configuration file.", "Default: sync.yml") { |v| options[:config] = v }
      
      opts.separator ""

      opts.on("-h", "--help", "Show this help message.") { puts opts; exit }
    end
  end

  def parse!
    parser.parse! @argv
    @operation = self.class.command

    @arguments = @argv
  end

  def run!
    if OPERATIONS.include?(@operation)
      run_command
    else
      abort "Unknown operation: #{@operation}. Use one of #{OPERATIONS.join(', ')}"
    end
  end

  def run_command
    case @operation
    when 'backup'
      cmd_backup
    when 'restore'
      cmd_restore
    end
  end

  # return a firefox profile path found first
  def firefox_profile_path
    return "#{@config["firefox_profile_prefix"]}/#{@config["firefox_profile_name"]}" if @config["firefox_profile_name"]
    # search profile dirs
    Dir.glob("#{File.expand_path(@config["firefox_profile_prefix"])}/*") do |item|
      return item if File.directory?(item)
    end
    logger.warn("cannot find firefox profile directory")
    nil
  end

  def cmd_backup
    @config["secret_files"].each do |file|
      if file.include?('__FIREFOX_PROFILE__')
        file.gsub!('__FIREFOX_PROFILE__', @firefox_profile_path)
      end
      `#{self.class.rsync} -r '#{File.expand_path(file)}' '#{@config["backup_dir"]}'`
    end
  end

  def cmd_restore
    ### insert secret_files into @basename_hash
    @basename_hash = {}
    @config["secret_files"].each do |file|
      if file.include?('__FIREFOX_PROFILE__')
        file.gsub!('__FIREFOX_PROFILE__', @firefox_profile_path)
      end
      @basename_hash[File.basename(file)] = file
    end
    Dir.glob("#{@config["backup_dir"]}/.*\0#{@config["backup_dir"]}/*") do |item|
      next if self.class.skip_item?(item)
      `#{self.class.rsync} -r '#{@config["backup_dir"]}/#{item}' '#{File.expand_path(@basename_hash[item])}'`
    end
  end
end
