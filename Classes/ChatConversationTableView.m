/* ChatRoomTableViewController.m
 *
 * Copyright (C) 2012  Belledonne Comunications, Grenoble, France
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 */

#import "LinphoneManager.h"
#import "ChatConversationTableView.h"
#import "UIChatBubbleTextCell.h"
#import "UIChatBubblePhotoCell.h"
#import "PhoneMainView.h"

static const CGFloat CELL_MIN_HEIGHT = 50.0f;
static const CGFloat CELL_MIN_WIDTH = 150.0f;
static const CGFloat CELL_MESSAGE_X_MARGIN = 26.0f + 10.0f;
static const CGFloat CELL_MESSAGE_Y_MARGIN = 36.0f;
static const CGFloat CELL_FONT_SIZE = 17.0f;
static const CGFloat CELL_IMAGE_HEIGHT = 100.0f;
static const CGFloat CELL_IMAGE_WIDTH = 100.0f;
static UIFont *CELL_FONT = nil;

@implementation ChatConversationTableView

@synthesize chatRoomDelegate;

#pragma mark - Lifecycle Functions

- (void)dealloc {
	[self clearMessageList];
}

#pragma mark - ViewController Functions

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	self.tableView.accessibilityIdentifier = @"Chat list";
	[self reloadData];
}

#pragma mark -

- (void)clearMessageList {
	if (messageList) {
		ms_list_free_with_data(messageList, (void (*)(void *))linphone_chat_message_unref);
		messageList = nil;
	}
}

- (void)updateData {
	if (!chatRoom)
		return;
	[self clearMessageList];
	self->messageList = linphone_chat_room_get_history(chatRoom, 0);

	// also append transient upload messages because they are not in history yet!
	for (FileTransferDelegate *ftd in [[LinphoneManager instance] fileTransferDelegates]) {
		const LinphoneAddress *ftd_peer =
			linphone_chat_room_get_peer_address(linphone_chat_message_get_chat_room(ftd.message));
		const LinphoneAddress *peer = linphone_chat_room_get_peer_address(chatRoom);
		if (linphone_address_equal(ftd_peer, peer) && linphone_chat_message_is_outgoing(ftd.message)) {
			LOGI(@"Appending transient upload message %p", ftd.message);
			self->messageList = ms_list_append(self->messageList, linphone_chat_message_ref(ftd.message));
		}
	}
}

- (void)reloadData {
	[self updateData];
	[self.tableView reloadData];
	[self scrollToLastUnread:false];
}

- (void)addChatEntry:(LinphoneChatMessage *)chat {

	messageList = ms_list_append(messageList, linphone_chat_message_ref(chat));
	int pos = ms_list_size(messageList) - 1;

	NSIndexPath *indexPath = [NSIndexPath indexPathForRow:pos inSection:0];
	[self.tableView beginUpdates];
	[self.tableView insertRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationFade];
	[self.tableView endUpdates];
}

- (void)updateChatEntry:(LinphoneChatMessage *)chat {
	NSInteger index = ms_list_index(self->messageList, chat);
	if (index < 0) {
		LOGW(@"chat entry doesn't exist");
		return;
	}
	[self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:index inSection:0]]
						  withRowAnimation:FALSE]; // just reload
	return;
}

- (void)scrollToBottom:(BOOL)animated {
	[self.tableView reloadData];
	int count = ms_list_size(messageList);
	if (count) {
		[self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:(count - 1)inSection:0]
							  atScrollPosition:UITableViewScrollPositionBottom
									  animated:YES];
	}
}

- (void)debugMessages {
	if (!messageList) {
		LOGE(@"No data to debug");
		return;
	}
	MSList *item = self->messageList;
	int count = 0;
	while (item) {
		LinphoneChatMessage *msg = (LinphoneChatMessage *)item->data;
		LOGI(@"Message %d: %s", count++, linphone_chat_message_get_text(msg));
		item = item->next;
	}
}

- (void)scrollToLastUnread:(BOOL)animated {
	if (messageList == nil || chatRoom == nil) {
		return;
	}

	int index = -1;
	int count = ms_list_size(messageList);
	// Find first unread & set all entry read
	for (int i = 0; i < count; ++i) {
		int read = linphone_chat_message_is_read(ms_list_nth_data(messageList, i));
		if (read == 0) {
			if (index == -1)
				index = i;
		}
	}
	if (index == -1) {
		index = count - 1;
	}

	linphone_chat_room_mark_as_read(chatRoom);

	// Scroll to unread
	if (index >= 0) {
		[self.tableView.layer removeAllAnimations];
		[self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:index inSection:0]
							  atScrollPosition:UITableViewScrollPositionTop
									  animated:animated];
	}
}

#pragma mark - Property Functions

- (void)setChatRoom:(LinphoneChatRoom *)room {
	chatRoom = room;
	[self reloadData];
}

#pragma mark - UITableViewDataSource Functions

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return ms_list_size(self->messageList);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSString *kCellId = nil;
	LinphoneChatMessage *chat = ms_list_nth_data(self->messageList, (int)[indexPath row]);
	if (linphone_chat_message_get_file_transfer_information(chat) ||
		linphone_chat_message_get_external_body_url(chat)) {
		kCellId = NSStringFromClass(UIChatBubblePhotoCell.class);
	} else {
		kCellId = NSStringFromClass(UIChatBubbleTextCell.class);
	}
	UIChatBubbleTextCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellId];
	if (cell == nil) {
		cell = [[NSClassFromString(kCellId) alloc] initWithIdentifier:kCellId];
	}
	[cell setChatMessage:chat];
	[cell setChatRoomDelegate:chatRoomDelegate];
	return cell;
}

#pragma mark - UITableViewDelegate Functions

- (void)tableView:(UITableView *)tableView
	commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
	 forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (editingStyle == UITableViewCellEditingStyleDelete) {
		[tableView beginUpdates];
		LinphoneChatMessage *chat = ms_list_nth_data(self->messageList, (int)[indexPath row]);
		if (chat) {
			linphone_chat_room_delete_message(chatRoom, chat);
			messageList = ms_list_remove(messageList, chat);

			[tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath]
							 withRowAnimation:UITableViewRowAnimationBottom];
		}
		[tableView endUpdates];
	}
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)aTableView
		   editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
	// Detemine if it's in editing mode
	if (self.editing) {
		return UITableViewCellEditingStyleDelete;
	}
	return UITableViewCellEditingStyleNone;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	LinphoneChatMessage *message = ms_list_nth_data(self->messageList, (int)[indexPath row]);
	return [self.class viewSize:message width:[self.view frame].size.width].height;
}

#pragma mark - Cell dimension

+ (CGSize)viewSize:(LinphoneChatMessage *)message width:(int)width {
	CGSize messageSize;
	const char *url = linphone_chat_message_get_external_body_url(message);
	if (url == nil && linphone_chat_message_get_file_transfer_information(message) == NULL) {
		NSString *text = [UIChatBubbleTextCell TextMessageForChat:message];
		if (CELL_FONT == nil) {
			CELL_FONT = [UIFont systemFontOfSize:CELL_FONT_SIZE];
		}
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 70000
		if (UIDevice.currentDevice.systemVersion.doubleValue >= 7) {
			messageSize =
				[text boundingRectWithSize:CGSizeMake(width - CELL_MESSAGE_X_MARGIN, CGFLOAT_MAX)
								   options:(NSStringDrawingUsesLineFragmentOrigin |
											NSStringDrawingTruncatesLastVisibleLine | NSStringDrawingUsesFontLeading)
								attributes:@{
									NSFontAttributeName : CELL_FONT
								} context:nil]
					.size;
		} else
#endif
		{
			messageSize = [text sizeWithFont:CELL_FONT
						   constrainedToSize:CGSizeMake(width - CELL_MESSAGE_X_MARGIN, 10000.0f)
							   lineBreakMode:NSLineBreakByTruncatingTail];
		}
	} else {
		messageSize = CGSizeMake(CELL_IMAGE_WIDTH, CELL_IMAGE_HEIGHT);
	}
	messageSize.height += CELL_MESSAGE_Y_MARGIN;
	if (messageSize.height < CELL_MIN_HEIGHT)
		messageSize.height = CELL_MIN_HEIGHT;
	messageSize.width += CELL_MESSAGE_X_MARGIN;
	if (messageSize.width < CELL_MIN_WIDTH)
		messageSize.width = CELL_MIN_WIDTH;
	return messageSize;
}

@end
