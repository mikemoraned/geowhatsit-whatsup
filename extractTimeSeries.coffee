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

regionFilePattern = /.+\/(\d+)\/regions$/

positions = {}
timeSeries = {}
FS.listTree(argv.dir).then((entries) =>
  regionFileNames =
    _.filter(entries, (e) => regionFilePattern.test(e))
  batches = batchUp(regionFileNames)
  console.log("Files to read: #{regionFileNames.length}")
  console.log("Batches: #{batches.length}")

  reads = (fileNames) =>
    _.map(fileNames, (f) =>
        FS.read(f).then((content) =>
          try
            { timestamp: parseInt(f.match(regionFilePattern)[1]), content: JSON.parse(content) }
          catch e
            console.warn("Ignoring #{f}: #{e}")
            null
        )
    )

  dispatchBatch = (index, batches) =>
    if index < batches.length
      batch = batches[index]
      console.log("Doing batch #{index} of length #{batch.length}")
      Q.all(reads(batch))
      .then(
        (filesRead) =>
          for fileRead in filesRead
#            console.dir(fileRead)
            if fileRead?
#              console.log(fileRead.timestamp)
              for entry in fileRead.content
#                console.dir(entry)
                positions[entry.name] = entry.geo
                if not timeSeries[entry.name]?
                  timeSeries[entry.name] = {}
                timeSeries[entry.name][fileRead.timestamp] = entry.summary.tweets
          dispatchBatch(index + 1, batches)
        ,
        (error) =>
          console.error(error)
        )

  dispatchBatch(0, batches)
).then(() =>
#  console.dir(positions)
#  console.dir(timeSeries)
  out = for name, geo of positions
    {
      name: name
      geo: geo
      timeSeries: timeSeries[name]
    }
  FS.write(argv.out, JSON.stringify(out)).then(() =>
    console.log("Write #{out.length} entries to #{argv.out}")
  )
)
.fail((error) =>
    console.error(error)
)

