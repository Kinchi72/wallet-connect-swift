//
//  ViewController.swift
//  WalletConnectApp
//
//  Created by Tao Xu on 3/29/19.
//  Copyright © 2019 Trust. All rights reserved.
//

import UIKit
import WallectConnect
import PromiseKit
import TrustWalletCore

class ViewController: UIViewController {

    @IBOutlet weak var uriField: UITextField!
    @IBOutlet weak var addressField: UITextField!
    @IBOutlet weak var chainIdField: UITextField!
    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var approveButton: UIButton!

    var interactor: WCInteractor?
    let clientMeta = WCPeerMeta(name: "WallectConnect SDK", url: "https://github.com/WalletConnect/swift-walletconnect-lib")

    let privateKey = PrivateKey(data: Data(hexString: "ba005cd605d8a02e3d5dfd04234cef3a3ee4f76bfbad2722d1fb5af8e12e6764")!)!

    var defaultAddress: String = ""
    var defaultChainId: Int = 1

    override func viewDidLoad() {
        super.viewDidLoad()

        let string = "wc:223fec05-fc2b-46b9-801d-cac76b3c80bf@1?bridge=https%3A%2F%2Fbridge.walletconnect.org&key=080ffccf7d8b106ecb4c14e6dd5de42ff06ae85317f8fcf283315da4e20166c8"

        defaultAddress = CoinType.ethereum.deriveAddress(privateKey: privateKey)
        uriField.text = string
        addressField.text = defaultAddress
        chainIdField.text = "1"
        chainIdField.textAlignment = .center
        approveButton.isEnabled = false
    }

    func connect(session: WCSession) {
        print("==> session", session)
        let interactor = WCInteractor(session: session, meta: clientMeta)
        let accounts = [defaultAddress]
        let chainId = defaultChainId
        interactor.onSessionRequest = { [weak self] (id, peer) in
            let message = [peer.name, peer.url].joined(separator: "\n")
            let alert = UIAlertController(title: "Session Request", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Reject", style: .cancel, handler: { _ in
                self?.interactor?.rejectSession().cauterize()
            }))
            alert.addAction(UIAlertAction(title: "Approve", style: .default, handler: { _ in
                self?.interactor?.approveSession(accounts: accounts, chainId: chainId).cauterize()
            }))
            self?.show(alert, sender: nil)
        }

        interactor.onEthSign = { [weak self] (id, params) in
            let alert = UIAlertController(title: "eth_sign", message: params[1], preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
            alert.addAction(UIAlertAction(title: "Sign", style: .default, handler: { _ in
                let signed = "0x745e32f38f7ac950bd00cd6522428f8658951ba6c1174cba561b866af023bb8279c77924e87edbc46d693a13f72721c251cfdda5ac47d53379b1fb6404eb12391b"
                self?.interactor?.approveRequest(id: id, result: signed).cauterize()
            }))
            self?.show(alert, sender: nil)
        }

        interactor.onEthSendTransaction = { [weak self] (id, params) in
            let data = try! JSONEncoder().encode(params[0])
            let message = String(data: data, encoding: .utf8)
            let alert = UIAlertController(title: "eth_sendTransaction", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Reject", style: .destructive, handler: { _ in
                self?.interactor?.rejectRequest(id: id, message: "I don't have ethers").cauterize()
            }))
            self?.show(alert, sender: nil)
        }

        interactor.onBnbSign = { [weak self] (id, params) in
            let data = try! JSONEncoder().encode(params[0])
            let message = String(data: data, encoding: .utf8)
            let alert = UIAlertController(title: "bnb_sign", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
            alert.addAction(UIAlertAction(title: "Sign", style: .default, handler: { [weak self] _ in
                self?.signBnbOrder(id: id, params: params)
            }))
            self?.show(alert, sender: nil)
        }

        interactor.connect().done { [weak self] connected in
            self?.connectionStatusUpdated(connected)
        }.cauterize()

        self.interactor = interactor
    }

    func approve(accounts: [String], chainId: Int) {
        interactor?.approveSession(accounts: accounts, chainId: chainId).done {
            print("<== approveSession done")
        }.cauterize()
    }

    func signBnbOrder(id: Int64, params: [WCBinanceOrderParam]) {
        let data = try! JSONEncoder().encode(params)
        let signature = privateKey.sign(digest: data, curve: .secp256k1)!
        let signed = WCBinanceOrderSigned(
            signature: signature.dropLast().hexString,
            publicKey: privateKey.getPublicKeySecp256k1(compressed: false).data.hexString
        )
        interactor?.approveBnbOrder(id: id, signed: signed).done({ confirm in
            print("<== approveBnbOrder", confirm)
        }).cauterize()
    }

    func connectionStatusUpdated(_ connected: Bool) {
        self.approveButton.isEnabled = connected
        self.connectButton.setTitle(!connected ? "Connect" : "Disconnect", for: .normal)
    }

    @IBAction func connectTapped() {
        guard let string = uriField.text, let session = WCSession(string: string) else {
            print("invalid uri: \(String(describing: uriField.text))")
            return
        }
        if let i = interactor, i.connected {
            i.killSession().done {  [weak self] in
                self?.approveButton.isEnabled = false
                self?.connectButton.setTitle("Connect", for: .normal)
            }.cauterize()
        } else {
            connect(session: session)
        }
    }

    @IBAction func approveTapped() {
        guard let address = addressField.text,
            let chainIdString = chainIdField.text else {
            print("empty address or chainId")
            return
        }
        guard let chainId = Int(chainIdString) else {
            print("invalid chainId")
            return
        }
        guard EthereumAddress.isValidString(string: address) || TendermintAddress.isValidString(string: address) else {
            print("invalid eth or bnb address")
            return
        }
        approve(accounts: [address], chainId: chainId)
    }
}
