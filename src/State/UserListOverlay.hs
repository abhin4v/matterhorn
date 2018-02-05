module State.UserListOverlay
  ( enterChannelMembersUserList
  , exitUserListMode
  , userListSelectDown
  , userListSelectUp
  , userListPageDown
  , userListPageUp
  )
where

import Data.Sequence (Seq)
import qualified Data.Vector as Vec
import qualified Data.Foldable as F
import Lens.Micro.Platform
import qualified Network.Mattermost.Endpoints as MM
import Network.Mattermost.Types

import qualified Brick.Widgets.List as L

import Types
import Types.Users
import State.Common

-- | Show the user list overlay for searching/showing members of the
-- current channel.
enterChannelMembersUserList :: MH ()
enterChannelMembersUserList = do
  cId <- use csCurrentChannelId
  enterUserListMode (ChannelMembers cId)

-- | Show the user list overlay with the given search scope, and issue a
-- request to gather the first search results.
enterUserListMode :: UserSearchScope -> MH ()
enterUserListMode scope = do
  csUserListOverlay.userListSearchScope .= scope
  csUserListOverlay.userListSelected .= Nothing
  asyncBeginSearch scope
  csMode .= UserListOverlay

asyncBeginSearch :: UserSearchScope -> MH ()
asyncBeginSearch scope = do
  csUserListOverlay.userListSearching .= True
  session <- use (csResources.crSession)
  doAsyncWith Preempt $ do
      chanUsers <- fetchInitialResults scope session
      return $ do
          let lst = listFromUserSearchResults $
                      (\u -> userInfoFromUser u True) <$> (Vec.fromList $ F.toList chanUsers)
          csUserListOverlay.userListSearchResults .= lst
          csUserListOverlay.userListSearching .= False

-- | Clear out the state of the user list overlay and return to the Main
-- mode.
exitUserListMode :: MH ()
exitUserListMode = do
  csUserListOverlay.userListSearchResults .= listFromUserSearchResults mempty
  csUserListOverlay.userListSelected .= Nothing
  csMode .= Main

-- | Move the selection up in the user list overlay by one user.
userListSelectUp :: MH ()
userListSelectUp = do
  csUserListOverlay.userListSearchResults %= L.listMoveUp

-- | Move the selection down in the user list overlay by one user.
userListSelectDown :: MH ()
userListSelectDown = do
  csUserListOverlay.userListSearchResults %= L.listMoveDown

-- | Move the selection up in the user list overlay by a page of users
-- (userListPageSize).
userListPageUp :: MH ()
userListPageUp = do
  csUserListOverlay.userListSearchResults %= L.listMoveBy (-1 * userListPageSize)

-- | Move the selection down in the user list overlay by a page of users
-- (userListPageSize).
userListPageDown :: MH ()
userListPageDown = do
  csUserListOverlay.userListSearchResults %= L.listMoveBy userListPageSize

-- | The number of users in a "page" for cursor movement purposes.
userListPageSize :: Int
userListPageSize = 10

-- | Perform an initial request for search results in the specified
-- scope.
fetchInitialResults :: UserSearchScope -> Session -> IO (Seq User)
fetchInitialResults (ChannelMembers cId) s = do
    let query = MM.defaultUserQuery
          { MM.userQueryPage = Just 0
          , MM.userQueryPerPage = Just 10000
          , MM.userQueryInChannel = Just cId
          }
    chanUserMap <- MM.mmGetUsers query s
    return chanUserMap
fetchInitialResults AllUsers _ = return mempty
