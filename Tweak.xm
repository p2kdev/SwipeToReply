@interface UIView (STR)
  - (id)_viewControllerForAncestor;
@end

@interface CKChatItem : NSObject
	-(BOOL)canInlineReply;
@end

@interface CKChatController : UIViewController
	-(void)showInlineReplyControllerForChatItem:(id)arg1 presentKeyboard:(BOOL)arg2;
	-(UIAction*)_inlineReplyActionForChatItem:(id)arg1;
	-(void)fullScreenBalloonViewController:(id)arg1 replyButtonPressedForChatItem:(id)arg2;
@end

@interface CKConversation : NSObject
	@property (nonatomic,readonly) NSString * serviceDisplayName;
@end

@interface CKTranscriptCollectionViewController : UIViewController
	@property (nonatomic, weak, readwrite) CKChatController *parentViewController;
	@property (nonatomic, copy, readwrite) NSArray *chatItems;
	@property (nonatomic, copy, readwrite) NSArray *associatedChatItems;
	@property (nonatomic,retain) CKConversation * conversation;
	-(void)balloonViewShowInlineReply:(id)arg1;
	-(id)chatItemForCell:(id)arg1;
@end

@interface CKBalloonImageView : UIView
@end

@interface CKBalloonView : CKBalloonImageView <UIGestureRecognizerDelegate>
	@property (assign,nonatomic) BOOL hasTail;
	@property (assign,nonatomic) char orientation;
@end

@interface CKImageBalloonView : CKBalloonView
@end

@interface CKTranscriptBalloonCell : UICollectionViewCell <UIGestureRecognizerDelegate>	
	@property (retain, nonatomic) UIImpactFeedbackGenerator *feedbackGenerator;
	@property (retain, nonatomic) UIImageView *replyImageView;
	@property (assign,nonatomic) CGPoint originalBubbleCenter; 
	@property (assign,nonatomic) BOOL shouldPlayFeedback;
	@property (nonatomic,retain) CKBalloonView * balloonView;
@end

static int swipeThreshold = 50;

%hook CKTranscriptBalloonCell
	%property (retain, nonatomic) UIImageView *replyImageView;
	%property (retain, nonatomic) UIImpactFeedbackGenerator *feedbackGenerator;
	%property (assign,nonatomic) CGPoint originalBubbleCenter; 
	%property (assign,nonatomic) BOOL shouldPlayFeedback;

	-(id)initWithFrame:(CGRect)arg1 {
		CKTranscriptBalloonCell *orig = %orig;
		if (orig) {
			self.feedbackGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];

			UIPanGestureRecognizer *replyGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
			replyGesture.delegate = self;
			[orig addGestureRecognizer:replyGesture];

			UIImage *replyImage = [UIImage systemImageNamed:@"arrowshape.turn.up.backward.fill"];
			replyImage = [replyImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
			self.replyImageView.frame = CGRectMake(0,0,24,24);
			self.replyImageView.userInteractionEnabled = NO;
			self.replyImageView = [[UIImageView alloc] initWithImage:replyImage];
			self.replyImageView.tintColor = [UIColor systemGrayColor];
			self.replyImageView.alpha = 0;
			[self addSubview:self.replyImageView];
		}
		return orig;
	}

	//We do not want the pan gesture to invoke for vertical pans like scrolling through the chats for example
	%new
	-(BOOL)gestureRecognizerShouldBegin:(UIPanGestureRecognizer *)panGestureRecognizer {
		CGPoint velocity = [panGestureRecognizer velocityInView:panGestureRecognizer.view];
		if (velocity.x < 0) {
			return false;
		}
		return fabs(velocity.x) > fabs(velocity.y);
	}

	%new
	-(void)handlePan:(UIPanGestureRecognizer *)recognizer
	{
		double screenCenter = [[UIScreen mainScreen] bounds].size.width/2;

		CKTranscriptCollectionViewController *transcriptViewController = [self _viewControllerForAncestor];
		CKChatItem *chatItem = [transcriptViewController chatItemForCell:self]; //Get the chat item for the panned bubble

		if (![chatItem canInlineReply]) //Not an iMessage so cannot reply in-line
			return;

		if (recognizer.state == UIGestureRecognizerStateBegan) {
			self.originalBubbleCenter = self.balloonView.center; //Capture the initial position of the bubble
			[self.feedbackGenerator prepare];
			self.shouldPlayFeedback = YES;

			if (self.originalBubbleCenter.x > screenCenter) //Reduce the swipe threshold for outgoing bubbles
				swipeThreshold = 25;				
		}

		int totalHorizontalMovement = self.balloonView.center.x - self.originalBubbleCenter.x;	

		CGPoint translation = [recognizer translationInView:recognizer.view];
		
		if ((totalHorizontalMovement <= 80 || translation.x < 0) && (totalHorizontalMovement >= 0 || translation.x > 0))
		{
			//Move the bubble
			self.balloonView.center = CGPointMake(self.balloonView.center.x + translation.x,
												self.balloonView.center.y);

			//Move the reply indicator
			self.replyImageView.frame = CGRectMake(self.balloonView.frame.origin.x - (self.originalBubbleCenter.x < screenCenter ? 30 : 35),
													self.balloonView.center.y - 12, 24, 24);												

			self.replyImageView.alpha = (totalHorizontalMovement - 20) * 0.02;

			[recognizer setTranslation:CGPointMake(0, 0) inView:recognizer.view];

			//Play haptic once
			if (totalHorizontalMovement > swipeThreshold && self.shouldPlayFeedback) {
				[self.feedbackGenerator impactOccurred];
				self.shouldPlayFeedback = NO;
			}			
		}

		if (recognizer.state == UIGestureRecognizerStateEnded)
		{	
			[UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
				self.replyImageView.alpha = 0;
				[self.balloonView setCenter: self.originalBubbleCenter]; //Reset the balloon to original position
			} completion:^(BOOL finished){
				if (totalHorizontalMovement > swipeThreshold) {
					[transcriptViewController.parentViewController showInlineReplyControllerForChatItem:chatItem presentKeyboard:YES]; //Present inline reply view for the specified chat item
				}					
			}];
		}
	}

%end
