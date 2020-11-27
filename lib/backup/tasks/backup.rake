namespace :backup do

  BACKUP_DIR = begin
    app_name =
        if Rails.application.class.respond_to?(:module_parent_name)
          Rails.application.class.module_parent_name
        else
          Rails.application.class.parent_name
        end.underscore

    File.join(Rails.root, [app_name, Rails.env].join('-'))
  end

  def mysqldump_database_args(db)
    args = {}
    args['--user'] = db['username']
    args['--password'] = db['password'] if db['password']
    args['--host'] = db['host'] if db['host']
    args['--port'] = db['port'] if db['port']

    args.map { |name, value| [name, value].join('=') }.join(' ')
  end

  desc 'Create backup of rails application data'
  task :create do
    FileUtils.rm_r(BACKUP_DIR) if File.directory?(BACKUP_DIR)
    FileUtils.mkdir_p(BACKUP_DIR)

    # backup mysql database
    unless ENV["skip_database"].present? && ENV["skip_database"] == "true"
      puts 'Backup MySQL database...'

      db = Rails.configuration.database_configuration[Rails.env]

      dump_file = File.join(BACKUP_DIR, "#{db['database']}.dump")
      sql_file = File.join(BACKUP_DIR, "#{db['database']}.sql")

      system(
        "mysqldump --no-tablespaces #{mysqldump_database_args(db)} #{db['database']} > #{dump_file}"
      )

      File.open(sql_file, 'w') { |f| f.puts "use #{db['database']};\n" }
      system("cat #{dump_file} >> #{sql_file}")
    end

    # backup uploads
    unless ENV["skip_uploads"].present? && ENV["skip_uploads"] == "true"
      src_dirs = [
        File.join(Rails.root, 'public', 'uploads'),
        File.join(Rails.root, 'private', 'uploads')
      ]

      src_dirs.each do |src_dir|
        dst_dir = File.join(BACKUP_DIR, src_dir[(Rails.root.to_s.length + 1)..-1])

        unless File.exist?(src_dir)
          puts "No backups found for #{src_dir}. Skipped."
        else
          puts "Backup uploads for #{src_dir}..."

          FileUtils.mkdir_p(File.dirname(dst_dir))
          FileUtils.cp_r(src_dir, dst_dir) unless File.directory?(dst_dir)
        end
      end
    end

    # Create tarball
    if ENV.key?('output_file')
      tar_file = ENV['output_file'] + (ENV['output_file'].end_with?('.tar') ? '' : '.tar')
    else
      tar_file = "#{BACKUP_DIR}.tar"
    end

    if system("tar -C #{File.dirname(BACKUP_DIR)} -cf #{tar_file} #{File.basename(BACKUP_DIR)}")
      FileUtils.rm_r(BACKUP_DIR)
    end
  end

  desc 'Restore backup of rails application data'
  task :restore do
    if ENV.key?('backup_file')
      tar_file = ENV['backup_file']
    else
      tar_file = "#{BACKUP_DIR}.tar"
    end
    abort "backup file '#{tar_file}' not found!" unless File.exist?(tar_file)

    print 'Confirm restoring from backup (Y/n): '
    confirmation = STDIN.gets.strip
    abort 'Aborted' unless confirmation == 'Y'

    system("tar -C #{File.dirname(BACKUP_DIR)} -xf #{tar_file}")

    # restore mysql database
    puts 'Restoring MySQL database...'

    Rake::Task['db:drop'].invoke
    Rake::Task['db:create'].invoke

    db = Rails.configuration.database_configuration[Rails.env]

    sql_file = File.join(BACKUP_DIR, "#{db['database']}.sql")
    system(
      "mysql #{mysqldump_database_args(db)} < #{sql_file}"
    )

    # restore uploads
    src_dirs = [
      File.join(BACKUP_DIR, 'public', 'uploads'),
      File.join(BACKUP_DIR, 'private', 'uploads')
    ]

    src_dirs.each do |src_dir|
      dst_dir = File.join(Rails.root, src_dir[(BACKUP_DIR.length + 1)..-1])

      unless File.exist?(src_dir)
        puts "No backups found for #{dst_dir}. Skipped."
      else
        puts "Restoring uploads for #{dst_dir}..."

        # Do not delete destination directory directly, as this may unlink the
        # symlink created by capistrano, thus copying the uploads not to the
        # shared, but the release directory.
        if File.directory?(dst_dir)
          Dir.glob(File.join(dst_dir, '*')).each do |file|
            FileUtils.rm_r(file)
          end
        end
        Dir.glob(File.join(src_dir, '*')).each do |file|
          FileUtils.cp_r(file, dst_dir)
        end
      end
    end

    # cleanup
    FileUtils.rm_r(BACKUP_DIR)
  end
end
