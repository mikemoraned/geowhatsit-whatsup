FS = require("q-io/fs")
Q = require("q")
_ = require("underscore")._
argv = require('optimist').argv

USAGE = "USAGE: #{process.argv[0]} #{process.argv[1]} --dir <directory to process> --out <file to output time series in>"

if not (argv.dir? and argv.out)
  console.error(USAGE)
  process.exit(1)

partition = (partitionSize) ->
  (list) ->
    groups = _.groupBy(list, (value, index) -> Math.floor(index/partitionSize))
    _.map(groups, (value) -> value)

batchUp = partition(100)

regionFilePattern = /.+(\d+)\/regions$/

FS.listTree(argv.dir).then((entries) =>
  regionFileNames =
    _.filter(entries, (e) => regionFilePattern.test(e))
  batches = batchUp(regionFileNames)
  console.log("Files to read: #{regionFileNames.length}")
  console.log("Batches: #{batches.length}")

  reads = (fileNames) =>
    _.map(fileNames, (f) =>
        FS.read(f).then((content) =>
          { name: f, content: content }
        )
    )

  dispatchBatch = (index, batches) =>
    if index < batches.length
      batch = batches[index]
      console.log("Doing batch #{index} of length #{batch.length}")
      Q.all(reads(batch))
      .then(
        (read) =>
#          console.dir(_.pluck(read, "name"))
          dispatchBatch(index + 1, batches)
        ,
        (error) =>
          console.error(error)
        )

  dispatchBatch(0, batches)
)