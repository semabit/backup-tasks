# Backup Tasks

This gem adds rake tasks helpful for making and restoring backups:

```ruby
rake backup:create # Create backup of rails application data
rake backup:restore # Restore backup of rails application data
```

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'backup-tasks', git: "git@github.com:semabit/backup-tasks.git"
```

And then execute:

    $ bundle
