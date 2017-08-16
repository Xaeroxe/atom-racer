{BufferedProcess} = require 'atom'
_ = require 'underscore-plus'
fs = require 'fs'
path = require 'path'

module.exports =
class RacerClient
  racer_bin: null
  rust_src: null
  cargo_home: null
  project_path: null
  candidates: null
  last_stderr: null
  last_process: null

  check_generator = (racer_action) ->
    (editor, row, col, cb) ->
      if !@process_env_vars()
        atom.notifications.addFatalError "Atom racer is not properly configured."
        cb null
        return

      options =
        command: @racer_bin
        args: [racer_action, row + 1, col, editor.getPath(), "-"]
        stdout: (output) =>
          return unless this_process == @latest_process
          parsed = @parse_single(output)
          @candidates.push(parsed) if parsed
          return
        stderr: (output) =>
            return unless this_process == @latest_process
            @last_stderr = output
            return
        exit: (code) =>
          return unless this_process == @latest_process
          @candidates = _.uniq(_.compact(_.flatten(@candidates)), (e) => e.word + e.file + e.type )
          cb @candidates
          if code == 3221225781
            atom.notifications.addWarning "racer could not find a required DLL; copy racer to your Rust bin directory"
          else if code != 0
            atom.notifications.addWarning "racer returned a non-zero exit code: #{code}\n#{@last_stderr}"
          return

      @candidates = []
      @latest_process = this_process = new BufferedProcess(options)
      this_process.process.stdin.write editor.getText()
      this_process.process.stdin.end()
      return

  check_completion: check_generator("complete")

  check_definition: check_generator("find-definition")

  find_racer_path: () ->
    for p in process.env.PATH.split(':')
      pArray = p.split('/')
      if pArray[pArray.length - 1] == 'racer'
        return p

  process_env_vars: ->
    config_is_valid = true

    atom.config.set('racer.racerBinPath', @find_racer_path())

    if !@racer_bin?
      conf_bin = atom.config.get("racer.racerBinPath")
      if conf_bin
        try
          stats = fs.statSync(conf_bin);
          if stats?.isFile()
            @racer_bin = conf_bin
    if !@racer_bin?
      config_is_valid = false
      atom.notifications.addFatalError "racer.racerBinPath is not set in your config."

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

  parse_single: (line) ->
    matches = []
    rcrgex = /MATCH (\w*)\,(\d*)\,(\d*)\,([^\,]*)\,(\w*)\,(.*)\n/mg
    while match = rcrgex.exec(line)
      if match?.length > 4
        candidate = {word: match[1], line: parseInt(match[2], 10), column: parseInt(match[3], 10), filePath: match[4], file: "this", type: match[5], context: match[6]}
        file_name = path.basename(match[4])
        candidate.file = file_name
        matches.push(candidate)
    return matches
