# restlog -- simple tool to log and manage data points from a RESTful web-based endpoint

## example

```
user1@home.local:~ $ ./restlog.sh init --datapt http://foo.local/rest/csv --hed http://foo.local/rest/csvhed --currentset today.csv --outputdir ./foo-data > foo.json
user1@home.local:~ $ cat foo.json
{
  "datapt": "http://foo.local/rest/csv",
  "hed": "http://foo.local/rest/csvhed",
  "currentset": "today.csv",
  "previousset": null,
  "archive": true,
  "outputdir": "/home/user1/foo-data"
}
```

### collect data point
Then, as e.g. in a [crontab](https://man7.org/linux/man-pages/man5/crontab.5.html), collect a single point of data:
```
5,35    *       *       *       *       /home/user1/bin/restlog.sh collect /home/user1/foo.json 
```
put this in a crontab and it will collect a single data point from `http://foo.local/rest/csv` every half hour and save it into a file called `today.csv`, in the directory `/home/user1/foo-data`. You don't have to do this in crontab, obviously, but this command is intended to be crontab friendly.

### rotate data set
If you want rotate the log file, say every week, add another crontab entry like this:
```
0       0       *       *       1       /home/user1/bin/restlog.sh rotate /home/user1/foo.json
```
This will move the `currentset` file (`today.csv` from our example) to archive, and create a new file, using the `hed` value to create the first line of the file, if desired.

## config file

`datapt` is used to get one data point when a *collect* command is run. It is provided to `curl -sS` if it looks like a URL. If it doesn't look like a URL, it will be executed as a command (so you can write your own customs cript). The output of this curl/command will be appended to the `currentset` file.

`hed` is an optional value that, if it looks like a URL, will be used to grab the column labels for suitable a set of data points. This value will be used when creating new `currentset` files. If it's not a URL, it will be interpretted as the the literal header line itself.

`currentset` is the file that data points are stored in when a *collect* command is run. Each new point gets appended to the bottom. The output of `hed` will be put at the top each time the file is created. The file will archived or deleted when `rotate` command is run.

`outputdir` is the directory where all other files will be written and stored to. It's safe to put the \*.json file there if you like.

`archive` is a boolean (defaulting to true) that, when a *rotate* command is run, will cause the cause the `currentset` file to be renamed (or copied, if `previousset` is set) to the current year-month-day-hour-minute (and will copy the file extension if present). If this value is set to false, no archive will be made. 

`previousset` is a file that the `currentset` will be renamed to when `rotate` command is run. Note that it will be renamed to this file. This will happen regardless of what value `archive` is.  If `archive` is true, then 

*NOTE*: if `archive` is false and `previousset` is null, then when the *rotate* command is run, the `currentset` file *WILL BE DELETED* 
