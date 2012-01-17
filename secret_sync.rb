require 'yaml'
require 'optparse'
require 'logger'
require 'fileutils'

class SecretSync
  OPERATIONS = %w(backup restore)

  # Parsed options
  attr_accessor :options
  attr_accessor :config
  attr_accessor :logger

  def self.rsync
    "/usr/bin/env rsync -auvz --delete"
  end

  def self.skip_item?(item)
    (File.basename(item) == '.' || File.basename(item) == '..')
  end

  def add_home(path)
    "#{ENV["HOME"]}/#{path}"
  end

  def initialize(argv, options = {})
    @argv = argv

    # Default options values
    @options = options

    parse!

    @logger = Logger.new(STDOUT)
    @logger.level = Logger::INFO

    @config = YAML.load_file(@options[:config] || 'sync.yml')
    @config["secret_files"] = @config["secret_files"].map {|f| add_home(f)}
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

  # return firefox profiles
  def current_firefox_profiles
    Dir.glob("#{add_home(@config["firefox_profile_prefix"])}/*").map {|dir| File.basename(dir)}
  end
  
  def backup_file(file, dir = "") 
    cmd = "#{self.class.rsync} '#{File.expand_path(file)}' '#{@config["backup_dir"]}#{"/#{dir}/" if !dir.empty?}'"
    puts cmd
    puts `#{cmd}`
  end

  def restore_file(file, dir)
    cmd = "#{self.class.rsync} '#{File.expand_path(file)}' '#{dir}'"
    puts cmd
    puts `#{cmd}`
  end

  def mkdir(dir)
    if !File.exists?(dir)
      FileUtils.mkdir_p(dir)
    end
  end

  def cmd_backup
    @firefox_profiles = current_firefox_profiles
    @config["secret_files"].each do |file|
      if file.include?('__FIREFOX_PROFILE__')
        #file.gsub!('__FIREFOX_PROFILE__', @firefox_profile_path)
        @firefox_profiles.each do |profile|
          mkdir("#{add_home(@config["firefox_profile_prefix"])}/#{profile}")
          backup_file(file.gsub('__FIREFOX_PROFILE__', "#{@config["firefox_profile_prefix"]}/#{profile}"), profile)
        end
      else
        backup_file(file)
      end
    end
    backup_file("#{File.dirname(add_home(@config["firefox_profile_prefix"]))}/profiles.ini")
  end

  def cmd_restore
    @firefox_profiles = Dir.glob("#{@config["backup_dir"]}/????????.*").find_all {|f| File.directory?(f)}.map {|f| File.basename(f)}
    ### insert secret_files into @basename_hash
    @basename_hash = {}
    @config["secret_files"].each do |file|
      if !file.include?('__FIREFOX_PROFILE__')
        @basename_hash[File.basename(file)] = File.dirname(file)
      end
    end
    Dir.glob("#{@config["backup_dir"]}/.*\0#{@config["backup_dir"]}/*") do |item|
      next if self.class.skip_item?(item)
      if (profile = @firefox_profiles.find {|i| item.match(i)})
        restore_file(item, "#{add_home(@config["firefox_profile_prefix"])}")
        next
      end
      if File.basename(item) == "profiles.ini"
        restore_file(item, "#{File.dirname(add_home(@config["firefox_profile_prefix"]))}")
        next
      end
      if @basename_hash[File.basename(item)].nil?
        puts "Backuped file #{item} is not listed in the targets of sync.yml (skipped)."
        next
      end
      restore_file(item, @basename_hash[File.basename(item)])
    end
    ### FIXME (hack for TrueCrypt file system)
    @config["secret_files"].each do |file|
      Dir.glob("#{File.expand_path(file)}\0#{File.expand_path(file)}/**") do |item|
        next if self.class.skip_item?(item)
        if File.directory?(item)
          File::chmod(0700, item)
          puts "chmod 0700 #{item}"
        else
          File::chmod(0600, item)
          puts "chmod 0600 #{item}"
        end
      end
    end
  end
end
