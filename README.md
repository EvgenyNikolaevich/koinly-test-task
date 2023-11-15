### Task

Read the task description on notion.

### Setup
```
bundle install
```

Make sure that specs are passing:
```
bundle exec rspec
```

### The code

You should start by looking at the file [spec/integration/api/csv_imports_spec.rb](spec/integration/api/csv_imports_spec.rb).

This is the spec file and it uses shared examples to import the specified csv file into our system and then calculates the final balances and puts them in an auto-generated snapshot file that you can look at to see if everything was imported correctly or not. The snapshot shows the final calculated balances and a couple of transactions (first and last) to help you understand how the data was imported.

- The CSV files are located in [spec/fixtures/files](spec/fixtures/files)
- The auto-generated snapshots are in [spec/fixtures/snapshots/csv_imports](spec/fixtures/snapshots/csv_imports)
- The actual code that does all the mapping and importing is located in the folder [lib/crypto_importers/mappers](lib/crypto_importers/mappers)

The [`BaseMapper`](lib/crypto_importers/mappers/base_mapper.rb) does most of the heavy lifting. If you open up the [`DefaultMapper`](lib/crypto_importers/mappers/default_mapper.rb), you will see an array of "mappings". Basically a mapper file can contain as many mappings as you want, a mapping defines how a file is imported. You have to set the "required_headers" to the columns in the csv file you are importing - this is important so that the correct mapping is used.

The first object in the `DefaultMapper` file has id "sample". It shows you all the fields in our database on the left side ex. `date`, `from_amount`, `from_currency` etc.

You will need to familiarize yourself with the `BaseMapper` and the way we are importing the various csv files.

### Adding a CSV mapper

Add the CSV file to the `spec/fixtures/files` folder and add a spec for it in `spec/integration/api/csv_imports_spec.rb`

Create a mapper class inside the `lib/crypto_importers/mappers/` folder. Look at the other mappers to figure things out.

#### How the mapping process works

1. This is a shared example that is executed for every `it_behaves_like "csv import"` line: [spec/shared/shared_examples_for_csv_imports.rb](spec/shared/shared_examples_for_csv_imports.rb)
2. Basically, we call the `CsvImportStarted#process` method in the shared example. This class detects the correct mapper by loading the headers from the CSV file and comparing them with the registered mappers (see `CsvImportStarted#potential_mappers` & `BaseMapper.confidence_score`).
3. If a mapper is found, the instance of the correct mapper class is initialized. After that, `import_and_commit!` (see `BaseMapper#import_and_commit!`) is called on this object.
4. Note that a mapper class can contain multiple "mappings". This is because many exchanges provide the same data in different CSV formats. Although the formats are similar, the header names may differ. By allowing multiple mappings in a single file, we can consolidate all code related to an exchange.
5. The final step is calling `CsvAdapter#commit` (a new `CsvAdapter` is initialized at the beginning of the import process). The purpose of the `CsvAdapter` is to publish the results to RabbitMQ, where they are then handled by the main app. If the import is successful, the list of transactions to import is published. Otherwise, an error is published. The `CsvAdapter#publish` method is [stubbed in the specs](spec/shared/shared_examples_for_csv_imports.rb#L22), and the payload is used to build a snapshot (JSON file).

### Adding an api importer
```
thor new_importer binance_exchange api_key api_secret
```

Look at the generated files and also files of other importers to get an idea of what needs to be done.

### Testing

The result of a CSV or API import can be viewed by adding `DUMP=1` before the rspec command:

```bash
DUMP=1 bundle exec rspec spec/integration/api/csv_imports_spec.rb:24
```

This will create a `dump` folder in the root of the project which contains all transactions along with the balance changes for each currency. Note that subsequent runs will regenerate this folder.
