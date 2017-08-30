{BufferedProcess} = require 'atom'
_ = require 'underscore-plus'
fs = require 'fs'
path = require 'path'

module.exports =
class RacerClient
  racer_bin: null
  rust_src: null
  cargo_home: null
  candidates: []
  last_stderr: null
  racer: null
  resultHandler: null
  commandQueue: []


  constructor: ->
    if !@process_env_vars()
      atom.notifications.addFatalError "Atom racer is not properly configured."
      return

    options =
      command: @racer_bin
      args: ['-i', 'tab-text', 'daemon']
      stdout: (output) =>
        [parsed, isLast] = @parse_lines(output)
        @candidates = @candidates.concat(parsed) if parsed?.length
        if isLast
          # pass the results to the result handler and reset state for next handler
          if @resultHandler then @resultHandler(@candidates)
          delete @resultHandler
          @candidates = []
          # run the next entry in the queue of waiting commands
          nextCommand = @commandQueue.shift()
          if nextCommand then nextCommand()
      stderr: (output) =>
          @last_stderr = output
          return
      exit: (code) =>
        if code == 3221225781
          atom.notifications.addWarning "racer could not find a required DLL; copy racer to your Rust bin directory"
        else if code != 0
          atom.notifications.addWarning "racer returned a non-zero exit code: #{code}\n#{@last_stderr}"
        return

    @racer = new BufferedProcess(options)

  destructor: ->
    # Kill the racer process when we're done
    @racer.process.kill()

  # run a racer command
  run_command: (racer_action, editor, row, col, cb) ->

    # register for output
    @resultHandler = (result) =>
      cb result

    # write our params
    params = [racer_action, row + 1, col, editor.getPath(), "-"].join('\t')
    @racer.process.stdin.write(params + '\n')
    @racer.process.stdin.write(editor.getText() + '\x04')

  # wait for our turn to run a command
  attempt_command: (args...) ->

    # if there is already a registered result handler
    if @resultHandler
      # wait at the end of the command queue
      @commandQueue.push( =>
        @attempt_command(args...)
      )
      return

    # otherwise run the command right away
    @run_command(args...)

  check_completion: (args...) ->
    @attempt_command("complete", args...)

  check_definition: (args...) ->
    @attempt_command("find-definition", args...)

  process_env_vars: ->
    config_is_valid = true

    if !@racer_bin?
      conf_bin = atom.config.get("racer.racerBinPath")
      if conf_bin
        try
          stats = fs.statSync(conf_bin);
          if stats?.isFile()
            @racer_bin = conf_bin
      else
        @racer_bin = 'racer'

    if !@rust_src?
      conf_src = atom.config.get("racer.rustSrcPath")
      if conf_src
        try
          stats = fs.statSync(conf_src);
          if stats?.isDirectory()
            @rust_src = conf_src

    if !@cargo_home?
      home = atom.config.get("racer.cargoHome")
      if home
        try
          stats = fs.statSync(home);
          if stats?.isDirectory()
            @cargo_home = home

    if config_is_valid
      if @rust_src?
        process.env.RUST_SRC_PATH = @rust_src
      if @cargo_home?
        process.env.CARGO_HOME = @cargo_home

    return config_is_valid

  parse_lines: (lines) ->
    matches = []
    isLast = false
    for line in lines.split('\n')
      result = line.split('\t')
      if result[0] == 'MATCH'
        candidate = {
          word: result[1],
          line: parseInt(result[2], 10),
          column: parseInt(result[3], 10),
          filePath: result[4],
          file: path.basename(result[4]) or "this",
          type: result[5],
          context: result[6]
        }
        matches.push(candidate)
      else if result[0] == 'END'
        isLast = true
    return [matches, isLast]
