# UAT v0.1.0

## BUGS

1. /Tested /Resolved [BUG] Study coordinator, create case page - words at top of page are cut off - SC (including edit case, diagnose case)
2. /Tested /Resolved [BUG] Some text gets cut off on diagnose case screen, e.g. gender field - SC (hide copy button for a lot of text fields)
3. /Tested /Resolved [BUG] App crash when tapping screen during searching case
4. /Tested /Resolved [BUG] Stability in case creation (backend error handling in AI inference service after timeout)
5. /Tested /Resolved [BUG] App crashes when tapping back when undiagnosed cases screen loading
6. /Tested /Resolved [BUG] Remove copy button for some text fields in edit case screen
7. /Tested /Resolved [BUG] Exception: Error fetching invite codes: Failed to fetch invite codes right after generate invite code
8. /Tested /Resolved [BUG] Exception: Registration failed: Exception: {"detail":"Error validating invite code: can't compare offset-naive and offset-aware datetimes"} when trying to register account with the new invite code
9. /Tested /Resolved [BUG] Double tap to zoom in/out image doesn't work, some images are surrounded by black view window, even when zoom in the view window is fixed (create case: consent form, edit case: consent form, biopsy report, oral cavity images, diagnose case: oral cavity images)
10. /Tested /Resolved [BUG] Missing created at and created by field data in diagnose case screen
11. /Tested /Resolved [BUG] Pixel overflow in my invite codes, admin invite code manager screen

## ENHANCEMENTS

1. /Tested /Resolved [ENHANCEMENT] Diagnose case - do not need to make all fields copy-able - SC (same item as previous resolved bug)
2. /Tested /Resolved [ENHANCEMENT] Should be able to enlarge image when reviewing - AN (edit case & diagnose case)
3. /Tested /Resolved [ENHANCEMENT] Add forgot password/change password function - SC. AN
4. /NA [ENHANCEMENT] Using existing email for account registration
5. /Tested /Resolved [ENHANCEMENT] Allow photo of consent form to be taken directly via the app as well as uploaded - AN (create case + biopsy report in edit case)
6. /Tested /Resolved [ENHANCEMENT] Can highlight all the missed mandatory fields when trying to submit at once? Right now it is only highlighting some in red - SC,AN (create case + diagnose case)
7. /Tested /Resolved [ENHANCEMENT] Modernize all UI (login, register, forgot password, home, role-based screens)
8. /Tested /Resolved [ENHANCEMENT] Duration for risk habits cannot leave blank? What should be entered if it is 'No" risk habits. Disable the duration section if No is selected - SC,AN (risk habits + oral hygiene products)
9. /Tested /Resolved [ENHANCEMENT] Restrict ID number field when adding patient to allow numerical input only? For NRIC you can also validate for the number of values as it is standardised, you can also auto-derive DOB and age from NRIC - SC, AN (NRIC: numbers only, PPN: capital letters and numbers only, DOB: auto derive from first 6 numbers of NRIC)
10. /Tested /Resolved [ENHANCEMENT] Apply clinical diagnoses dropdown list
11. /Tested /Resolved [ENHANCEMENT] Duration is free text? Can it be restricted to [number] WEEKS/MONTHS/YEARS , WEEKS/MONTHS/YEARS can be dropdown - SC, AN
12. /Tested /Resolved [ENHANCEMENT] Have a dropdown for ethnicity with others option that allows for free text, I recall we asked for this to be string but in hindsight this seems to be easier - AN
13. /Tested /Resolved [ENHANCEMENT] Can we include reason for low quality? Can use the dropdown list - SC, AN (export bundle: spreadsheet format)
14. /Tested /Resolved [ENHANCEMENT] Password for user registration, ideally different for user type and user (admin manage invite code screen)
15. /Tested /Resolved [ENHANCEMENT] Suggest that there is a next button to move onto the next image among the nine images instead of checking the dropdown - AN (Replace submit button with next button when diagnosis of all images are incomplete)
16. /Tested /Resolved [ENHANCEMENT] How would you search if you did not copy the case ID? - SC,AN (Show list of created case of the study coordinator, decrypt only when clicked)
17. /Tested /Resolved [ENHANCEMENT] Undiagnosed cases takes a long time to load (only decrypt the cases when a case is clicked for diagnose)
18. /Tested /Resolved [ENHANCEMENT] Notification mechanism to developer when AI inference service is down
19. /Nofix [ENHANCEMENT] Is it possible to have save as draft for clinician diagnosis? - SC, AN
20. /Nofix [ENHANCEMENT] Case submission and export bundle takes a while - AN
21. /Tested /Resolved [ENHANCEMENT] Make consent form, biopsy reports also zoomable?

## OTHERS

/Nofix [BUG] Cannot find cases after submission - SC (TBC)
/Nofix [BUG] Search not working - SC, AN [see screenshot] (TBC)
/Nofix [BUG] Could not test case editing, as cannot search cases after submitting because search not working - SC, AN (TBC)
/Nofix [BUG] I don't see the cases that I submitted with the study coordinator account. Am I supposed to? - SC,AN (TBC)

# UAT v0.2.0

## BUGS

1. /Improved [BUG] Study coordinator edit case does not reflect directly (Fix: respond first, then write to Firestore in the background > write to Firestore first, then respond)
2. /Improved [BUG] Study coordinator unable to find created case (happened on 8/12 around 3pm by Sara) (Fix: wait AI inference, then batch write case data & AI results > write case data to Firestore first, batch update AI results after AI inference)
3. /Nofix (Intended behaviour) [BUG] Name text input should not allow apostrophes (')
4. /Improved [BUG] Concurrency: Multiple users doing same action at the same time may cause conflicts (Moved heavy tasks to non-blocking background worker)

## ENHANCEMENTS

1. /Tested /Resolved [ENHANCEMENT] Update model to latest / best performing + threshold setting
2. /Tested /Resolved [ENHANCEMENT] No Lesion -> Normal Mucosa (add condition if lesion type consist of 1 clinical diagnosis, auto assign to it)
3. /Tested /Resolved [ENHANCEMENT] UserManager (get, list, edit, soft/hard delete, reactivate user)
   Test: Generate invite code > Register new clinician > Login clinician > Logout & Login admin > Edit user (name, email) > Logout & Login clinician > Logout & Login admin > Edit user (name, role, email) > Logout & Login clinician > Logout & Login admin > soft delete clinician > Logout & try Login clinician > Login admin > reactivate clinician > Logout & login clinician > Logout & login admin > hard delete clinician > Logout & try login clinician
4. /Resolved [ENHANCEMENT] Write comprehensive documentation
5. [ENHANCEMENT] Refactor MeMoSA Clinical Platform > MeMoSA Clinical Trial
