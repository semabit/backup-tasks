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

    args.map { |name, value| [name, "\"#{value}\""].join('=') }.join(' ')
  end

  def dumpfile_path(backup_dir: BACKUP_DIR)
    default_path = File.join(backup_dir, 'database.dump')

    # when restoring from a current tarball the default dumpfile should exist
    return default_path if File.exist?(default_path)

    # when restoring from an old tarball the default dumpfile may be named differently
    legacy_path = Dir.glob(File.join(backup_dir, '*.dump')).first
    return legacy_path if legacy_path.present?

    # when creating a tarball return the default dumpfile
    default_path
  end

  desc 'Create backup of rails application data'
  task :create do
    Rake::Task["backup:create:backup_dir"].invoke
    Rake::Task["backup:create:db"].invoke
    Rake::Task["backup:create:uploads"].invoke
    Rake::Task["backup:create:tarball"].invoke
  end

  namespace :create do
    desc 'Ensure clean BACKUP_DIR'
    task :backup_dir do
      FileUtils.rm_r(BACKUP_DIR) if File.directory?(BACKUP_DIR)
      FileUtils.mkdir_p(BACKUP_DIR)
    end

    desc 'Create backup of mysql database'
    task :db do
      unless ENV["skip_database"].present? && ENV["skip_database"] == "true"
        puts 'Backup MySQL database...'

        db = Rails.configuration.database_configuration[Rails.env]

        FileUtils.mkdir_p(File.dirname(dumpfile_path))
        system(
          "mysqldump --no-tablespaces #{mysqldump_database_args(db)} #{db['database']} > #{dumpfile_path}"
        )
      end
    end

    desc 'Create backup of uploads'
    task :uploads do
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
    end

    desc 'Create tarball'
    task :tarball do
      if ENV.key?('output_file')
        tar_file = ENV['output_file'] + (ENV['output_file'].end_with?('.tar') ? '' : '.tar')
      else
        tar_file = "#{BACKUP_DIR}.tar"
      end

      if system("tar -C #{File.dirname(BACKUP_DIR)} -cf #{tar_file} #{File.basename(BACKUP_DIR)}")
        FileUtils.rm_r(BACKUP_DIR)
      end
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

    # extract tarball and find out directory name
    files_before = Dir.glob(File.join(File.dirname(BACKUP_DIR), '*'))
    system("tar -C #{File.dirname(BACKUP_DIR)} -xf #{tar_file}")
    files_after = Dir.glob(File.join(File.dirname(BACKUP_DIR), '*'))

    backup_dir = (files_after - files_before).first
    abort "Could not determine backup directory. Maybe an old backup is still present?" unless backup_dir.present?

    # restore mysql database
    puts 'Restoring MySQL database...'

    Rake::Task['db:drop'].invoke
    Rake::Task['db:create'].invoke

    db = Rails.configuration.database_configuration[Rails.env]

    system(
      "mysql #{mysqldump_database_args(db)} #{db['database']} < #{dumpfile_path(backup_dir: backup_dir)}"
    )
    system(
      "bin/rails db:environment:set RAILS_ENV=#{Rails.env}"
    )

    # restore uploads
    src_dirs = [
      File.join(backup_dir, 'public', 'uploads'),
      File.join(backup_dir, 'private', 'uploads')
    ]

    src_dirs.each do |src_dir|
      dst_dir = File.join(Rails.root, src_dir[(backup_dir.length + 1)..-1])

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
    FileUtils.rm_r(backup_dir)
  end
end
