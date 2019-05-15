# Son of Nun - Ruby interface to the Joshua Project

The [Joshua Project](https://joshuaproject.net) is a tool for Christian missionaries which collects and distributes data about people groups, languages, and religious affiliation. Son of Nun is a Ruby library which facilitates querying and remixing the Joshua Project data.

## Examples

```Ruby
% irb -Ilib

require("sonofnun")
=> true

# How many Evangelical diaspora people are there?
Community.diaspora.sum(:EvangelicalPopulation)
=> 25240188

# Is France unreached?
Country.called("France").unreached?
=> true

# What, really?
Country.called("France").evangelical_percentage
=> 1.0

# What are the big Evangelical people groups of India called?
Country.called("India").communities.significant_evangelical_populations.map &:name
=> ["Garo of India", "Mizo of India", "Mizo Lushai of India"]
```

See the `examples/` directory for more examples.

## Requirements

As well as the Ruby gems in the Gemfile, you will need `wget` and `mdbtools` to import the data from the JP website. You will also need a MongoDB server.

If you are on OS X with Homebrew, you can install these with `brew install wget mdbtools mongodb`.

## Loading in the JP data

To download the data and convert it to CSV format:

    sh scripts/download-and-convert.sh

To then import the data into the Mongo database:

    ruby -Ilib scripts/import-csv-to-mongo.rb