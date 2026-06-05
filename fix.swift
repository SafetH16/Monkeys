        if let buffer = synthesizer.generateLevelUpChime() {
            let player = nextPlayer()
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            player.play()
        }
    }
