### Setup
```
bundle install
```

Make sure these specs are passing:
```
bundle exec rspec
```

### Adding an api importer

`thor new_importer binance_exchange api_key api_secret`

Look at the generated files and also files of other importers to get an idea of what needs to be done.

### Adding a CSV mapper
Add the csv file to the fixtures/files folder and add a spec for it in `spec/integration/api/csv_imports_spec.rb`

Create a mapper class inside the `lib/crypto_importers/mappers/` folder. Look at the other mappers to figure things out. For details about all the mapped fields, refer to the Engineering wiki.
