import DailySystemBroadcast

public class SampleHandler: DailyBroadcastSampleHandler {
    
    override init() {
        super.init(appGroupIdentifier: "group.co.daily.DailyDemo")
    }
    
}
