{-# OPTIONS_HADDOCK hide, prune #-}
module Handler.Home
    ( getHomeR
    , postHomeR
    ) where

import Import

import Handler.Home.LoadingSplash
import Handler.Home.PopupHelp
import Handler.Home.UIButtons
import Handler.Home.PanelServices
import Handler.Home.PanelGeometry
import Handler.Home.PanelInfo
import Handler.Home.PopupEdxGuide
import Handler.Home.LuciConnect
import Handler.Mooc.Comment
import Handler.Mooc.ExpertReview

getHomeR :: Handler Html
getHomeR = renderQuaView

postHomeR :: Handler Html
postHomeR = renderQuaView


renderQuaView :: Handler Html
renderQuaView = do

  muser <- maybeAuth
  let urole = muserRole muser
  mscId <- getsSafeSession userSessionScenarioId
  isEdx <- isJust <$> getsSafeSession userSessionEdxResourceId

  -- if the user is an owner of scenario, let him edit it!
  case (,,) urole <$> muser <*> mscId of
    Just (UR_STUDENT, Entity userId _, scId) -> runDB $ do
      scenario <- get scId
      when (fmap scenarioAuthorId scenario == Just userId) $
        lift (setSafeSession userSessionQuaViewMode "edit")
    _ -> return ()

  mscLink <- case mscId of
    Nothing -> return Nothing
    Just scId -> runDB $ do
      scenario <- get scId
      return $ (,) <$> fmap scenarioTaskId scenario
                   <*> fmap scenarioAuthorId scenario

  qua_view_mode <- fromMaybe "full" <$> getsSafeSession userSessionQuaViewMode
  let showFull = qua_view_mode == "full"

  commentsW <- maybe (pure mempty) viewComments mscId

  let writeExpertReviewW = mempty::Widget
  viewExpertReviewsW <- maybe (pure mempty) viewExpertReviews mscId

  showHelp <- if qua_view_mode == "view"
              then return False
              else case muser of
      Nothing -> return True
      Just (Entity uid _) -> runDB $ do
        mx <- getBy $ UserProperty uid "qua-view-show-help"
        case mx of
          Just (Entity _ (UserProp _ _ "false")) -> return False
          _ -> do
            _ <- upsert (UserProp uid "qua-view-show-help" "false") [UserPropValue =. "false"]
            return True

  -- connecting form + conteiners for optional content
  (lcConnectedClass, lcDisconnectedClass, luciConnectForm) <- luciConnectPane
  (popupScenarioList, luciScenariosPane) <- luciScenarios
  (uiButtonsGUI, uiButtonsSubmitPopup) <- uiButtons mscLink
  minimalLayout $ do

    -- add qua-view dependencies
    toWidgetHead
      [hamlet|
        <script src="@{StaticR js_numeric_min_js}" type="text/javascript">
        <script src="@{StaticR js_qua_view_js}"    type="text/javascript">
      |]

    -- write a function to retrieve settings from qua-server to qua-view
    toWidgetHead
      [julius|
        window['getQuaViewSettings'] = function getQuaViewSettings(f){
          var qReq = new XMLHttpRequest();
          qReq.onload = function (e) {
            if (qReq.readyState === 4) {
              if (qReq.status === 200) {
                f(JSON.parse(qReq.responseText));
              } else {f({});}
            }
          };
          qReq.onerror = function (e) {f({});};
          qReq.open("GET", "@{QuaViewSettingsR}", true);
          qReq.send();
        };
      |]

    setTitle "qua-kit"

    -- render all html
    $(widgetFile "qua-view")
