const { keccak256 } = require("@ethersproject/keccak256");
const { expect } = require("chai");

describe("MIPSMemory contract", function () {
  beforeEach(async function () {
    const MIPSMemory = await ethers.getContractFactory("MIPSMemory");
    mm = await MIPSMemory.deploy();
    console.log("deployed at", mm.address);
  })
  it("Keccak should work", async function () {
    await mm.AddLargePreimageInit(0);
    console.log("preimage initted");

    // empty
    async function tl(n) {
      const test = new Uint8Array(n)
      for (var i = 0; i < n; i++) test[i] = 0x62;
      console.log("test size", n)
      expect((await mm.AddLargePreimageFinal(test))[0]).to.equal(keccak256(test));
    }
    await tl(0)
    await tl(100)
    await tl(134)
    await tl(135)

    // block size is 136
    let dat = new Uint8Array(136)
    dat[0] = 0x61
    await mm.AddLargePreimageUpdate(dat);

    const hash = (await mm.AddLargePreimageFinal([]))[0];
    console.log("preimage updated");

    const realhash = keccak256(dat);
    console.log("comp hash is", hash);
    console.log("real hash is", realhash);
    expect(hash).to.equal(realhash);
  });
  it("oracle save should work", async function () {
    await mm.AddLargePreimageInit(4)

    let dat = new TextEncoder("utf-8").encode("hello world")
    const tst = await mm.AddLargePreimageFinal(dat)
    expect(tst[0]).to.equal(keccak256(dat))
    expect(tst[1].toNumber()).to.equal(11)
    expect(tst[2]).to.equal(0x6f20776f)
    console.log(tst)

    await mm.AddLargePreimageFinalSaved(dat)
  })
});