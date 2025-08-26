import DailySystemBroadcast

public class SampleHandler: DailyBroadcastSampleHandler {
    
    override init() {
        super.init(appGroupIdentifier: "group.new.example.daily")
    }
    
}
