open Mocha
open Test__Util

describe("Connection", () => {
  describe("Picked connection", () => {
    let agdaMockPath = ref("")
    let agdaMockTarget = ref(None)

    Async.before(
      async () => {
        // setup the Agda mock
        agdaMockPath := (await Target.Agda.mock(~version="2.7.0.1", ~name="agda-mock"))

        switch await Connection.Target.fromRawPath(agdaMockPath.contents) {
        | Ok(target) => agdaMockTarget := Some(target)
        | Error(_) => failwith("Got error when trying to construct a mock for Agda")
        }
      },
    )

    Async.it(
      "should return the previously picked connection",
      async () => {
        // access the Agda mock
        let agdaMockTarget = switch agdaMockTarget.contents {
        | Some(target) => target
        | None => failwith("Unable to access the Agda mock target")
        }

        // setup the momento
        let memento = State__Memento.make(None)
        await Connection.Target.setPicked(memento, Some(agdaMockTarget))

        let paths = [agdaMockPath.contents, "path/to/als"]

        let actual = await Connection__Target.getPicked(memento, paths)
        let expected = Some(agdaMockTarget)

        Assert.deepEqual(actual, expected)
      },
    )

    Async.it(
      "should return nothing when there's no previously picked connection",
      async () => {
        // setup the momento
        let memento = State__Memento.make(None)
        let paths = ["path/to/agda", "path/to/als"]

        let actual = await Connection__Target.getPicked(memento, paths)
        let expected = None

        Assert.deepEqual(actual, expected)
      },
    )

    Async.after(
      async () => {
        // cleanup the Agda mock
        switch agdaMockTarget.contents {
        | Some(target) =>
          Target.Agda.destroy(target)
          agdaMockTarget := None
        | None => ()
        }
      },
    )
  })
})
