FS = require("q-io/fs")
Q = require("q")
_ = require("underscore")._
argv = require('optimist').argv

USAGE = "USAGE: #{argv.$0} --dir <directory to process> --since <millis since epoch> [--show-differences]--out <file to output time series in>"

if not (argv.dir? and argv.out and argv.since)
  console.error(USAGE)
  process.exit(1)

since = parseInt(argv.since)

console.dir(argv)

partition = (partitionSize) ->
  (list) ->
    groups = _.groupBy(list, (value, index) -> Math.floor(index/partitionSize))
    _.map(groups, (value) -> value)

batchUp = partition(100)

regionFilePattern = /.+\/(\d+)\/regions$/

positions = {}
timeSeries = {}
max = Number.MIN_VALUE
min = Number.MAX_VALUE
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
      console.log("Doing batch #{index + 1}/#{batches.length} of length #{batch.length}")
      Q.all(reads(batch))
      .then(
        (filesRead) =>
          for fileRead in filesRead
#            console.dir(fileRead)
            if fileRead?
#              console.log(fileRead.timestamp)
              for entry in fileRead.content
#                console.dir(entry)
                if fileRead.timestamp >= since
                  positions[entry.name] = entry.geo
                  tweetsAtTimestamp = timeSeries[fileRead.timestamp]
                  if not tweetsAtTimestamp?
                    tweetsAtTimestamp = timeSeries[fileRead.timestamp] = {}
                  tweets = entry.summary.tweets
                  tweetsAtTimestamp[entry.name] = tweets
                  min = Math.min(min, tweets)
                  max = Math.max(max, tweets)
          dispatchBatch(index + 1, batches)
        ,
        (error) =>
          console.error(error)
        )

  dispatchBatch(0, batches)
).then(() =>
#  console.dir(positions)
#  console.dir(timeSeries)
  out =
    {
      range: {
        min: min
        max: max
      }
      data: for timestamp, tweetsAtTimestamp of timeSeries
        {
          timestamp: timestamp
          snapshot: for name, tweets of tweetsAtTimestamp
            {
              name: name
              geo: positions[name]
              summary: {
                tweets: tweets
              }
            }
        }
    }

  if (argv['show-differences'])
    console.log("Finding differences over time")
    max = Number.MIN_VALUE
    min = Number.MAX_VALUE
    out.data = for pair in _.chain(out.data).zip(_.rest(out.data)).filter((p) => p[1]?).value()
#      console.dir(pair[1])
#      console.log(pair[1].timestamp)
#      console.log("#{min}->#{max}")
      diffs = for entry in pair[1].snapshot
        latestCount = entry.summary.tweets
        prevEntry = _.filter(pair[0].snapshot, (e) => e.name == entry.name)
        diff = if prevEntry[0]?
          prevCount = prevEntry[0].summary.tweets
          latestCount - prevCount
        else
          0
        #        console.log("%s,%s,%s", prevCount, latestCount, diff)
        min = Math.min(min, diff)
        max = Math.max(max, diff)
        {
          name: entry.name
          geo: entry.geo
          summary: {
            tweets: diff
          }
        }
      {
        timestamp: pair[1].timestamp
        snapshot: _.filter(diffs, (d) => d.summary.tweets > 0)
      }
    out.range = {
      min: min
      max: max
    }

  FS.write(argv.out, JSON.stringify(out)).then(() =>
    console.log("Wrote entries to #{argv.out}")
  )
)
.fail((error) =>
    console.error(error)
)

