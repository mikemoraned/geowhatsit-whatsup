FS = require("q-io/fs")
Q = require("q")
_ = require("underscore")._
argv = require('optimist').argv

USAGE = "USAGE: #{process.argv[0]} #{process.argv[1]} --dir <directory to process> --out <file to output time series in>"

if not (argv.dir? and argv.out)
  console.error(USAGE)
  process.exit(1)

batch = (batchSize) =>
  split = (batches, value, index) =>
    batches[index / batchSize] = value
    batches
  (list) =>
    _.reduce(list, split, [])

FS.listTree(argv.dir).then((entries) =>
  regionFileNames =
    _.chain(entries).filter((e) => /.+(\d+)\/regions$/.test(e)).value()
  batches = batch(10)(regionFileNames)
#  console.dir(regionFileNames)

#  nextBatch = (batches, index) =>
#    if index < batches.length
#      Q.all(for regionFileName in batch
#        FS.read(regionFileName).then((content) =>
#          console.log("Read #{regionFileName}")
#          { name: regionFileName, content: content }
#        ))
#      .then(
#          (read) =>
#            console.log("#{read.length}")
#            console.dir(_.pluck(read, "name"))
#        ,
#        (error) =>
#          console.error(error)
#        )
#      .then(nextBatch(batches, index - 1))

  for batch in batches
    Q.all(for regionFileName in batch
      FS.read(regionFileName).then((content) =>
        console.log("Read #{regionFileName}")
        { name: regionFileName, content: content }
      ))
      .then(
        (read) =>
          console.log("#{read.length}")
          console.dir(_.pluck(read, "name"))
        ,
        (error) =>
          console.error(error)
      )
)