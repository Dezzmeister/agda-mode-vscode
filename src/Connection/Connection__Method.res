// like Source.t but with more info for display
type source =
  | FromFile(string) // path of the program
  | FromCommand(string) // name of the command
  | FromTCP(int, string) // port, host
  | FromGitHub(Connection__Method__GitHub.Repo.t, Connection__Method__GitHub.Release.t, Connection__Method__GitHub.Asset.t)

let sourceToString = source =>
  switch source {
  | FromFile(path) => "File: " ++ path
  | FromCommand(name) => "Command: " ++ name
  | FromTCP(port, host) => "TCP: " ++ string_of_int(port) ++ " " ++ host
  | FromGitHub(repo, release, asset) =>
    "GitHub: " ++
    Connection__Method__GitHub.Repo.toString(repo) ++
    " " ++
    Connection__Method__GitHub.Release.toString(release) ++
    " " ++
    Connection__Method__GitHub.Asset.toString(asset)
  }

// Means of Inter-process communication
type t =
  | ViaPipe(string, array<string>, option<Connection__Target__ALS__LSP__Binding.executableOptions>, source) // command, args, options, source
  | ViaTCP(int, string, source) // port, host
