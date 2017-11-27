class Backup::Tasks::Railtie < Rails::Railtie
  rake_tasks do
    load 'backup/tasks/backup.rake'
  end
end
