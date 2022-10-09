const Factory = artifacts.require("WalletFactory")
const Wallet = artifacts.require("Wallet")


module.exports = async function (d) {
    await d.deploy(Wallet);
    await d.deploy(Factory, Wallet.address)

    console.log(`
        Wallet Factory:        ${Factory.address}
        Wallet Implementation: ${Wallet.address}
    `)
}